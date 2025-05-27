# Gemfile:
# gem 'ruby-ami'

require 'ruby-ami'

class AsteriskService
  attr_reader :channel, :ami_client, :host, :port, :username, :password

  def initialize(channel)
    @channel = channel
    @host = channel.host
    @port = channel.port
    @username = channel.username
    @password = channel.password
    @ami_client = nil
    @event_handlers = {}
    @account_id = channel.account_id
    @inbox_id = channel.inbox.id
  end

  def connect
    return true if @ami_client&.connected?

    @ami_client = RubyAMI::Stream.new(@host, @port, @username, @password, connect_timeout: 5, read_timeout: 2)
    @ami_client.connect
    Rails.logger.info "AsteriskService: Successfully connected to AMI at #{@host}:#{@port} for account #{@account_id}, inbox #{@inbox_id}"
    login
    register_default_event_handlers
    start_event_listener
    true
  rescue RubyAMI::Error => e
    Rails.logger.error "AsteriskService: Failed to connect to AMI: #{e.message}"
    @ami_client = nil
    false
  rescue StandardError => e
    Rails.logger.error "AsteriskService: An unexpected error occurred during connection: #{e.message}"
    @ami_client = nil
    false
  end

  def disconnect
    return unless @ami_client&.connected?
    stop_event_listener
    @ami_client.logout
    @ami_client.disconnect
    Rails.logger.info "AsteriskService: Disconnected from AMI at #{@host}:#{@port}"
  ensure
    @ami_client = nil
  end

  def connected?
    @ami_client&.connected? || false
  end

  def send_action(action_name, params = {})
    raise "Not connected to Asterisk AMI" unless connected?

    action = RubyAMI::Action.new(action_name, params)
    response = @ami_client.send_action(action)
    Rails.logger.info "AsteriskService: Sent action #{action_name} with params #{params}. Response: #{response.inspect}"
    response # Or parse and return a more structured result
  rescue RubyAMI::Error => e
    Rails.logger.error "AsteriskService: Error sending action #{action_name}: #{e.message}"
    nil # Or raise a custom error
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Unexpected error sending action #{action_name}: #{e.message}"
    nil
  end

  def register_event_handler(event_name, &block)
    @event_handlers[event_name.downcase] ||= []
    @event_handlers[event_name.downcase] << block
    Rails.logger.info "AsteriskService: Registered handler for event '#{event_name.downcase}'"
  end

  # Specific event handler methods
  def handle_new_channel_event(event)
    caller_id_num = event.attributes['CallerIDNum']
    caller_id_name = event.attributes['CallerIDName']
    unique_id = event.attributes['Uniqueid']
    channel_state_desc = event.attributes['ChannelStateDesc'] # e.g., Ring, Up

    Rails.logger.info "AsteriskService: NewChannel event received. CallerID: #{caller_id_num} (#{caller_id_name}), UniqueID: #{unique_id}, State: #{channel_state_desc}"

    # We are interested in incoming calls that are starting to ring or are established.
    # Adjust this logic based on your specific Asterisk dialplan and event flow.
    # For instance, you might only want to create a conversation when the call is answered ('Up')
    # or immediately when it starts ringing ('Ring').
    # Here, we'll consider 'Ring' or 'Ringing' as the trigger.
    return unless ['Ring', 'Ringing'].include?(channel_state_desc) && caller_id_num.present? && unique_id.present?

    # Additional attributes to pass to the job
    call_details = {
      caller_id_num: caller_id_num,
      caller_id_name: caller_id_name,
      asterisk_unique_id: unique_id,
      channel_state_desc: channel_state_desc,
      # You might want to add context, extension, etc., if available and relevant
      # context: event.attributes['Context'],
      # extension: event.attributes['Exten'],
    }

    Rails.logger.info "AsteriskService: Enqueuing ConversationFromAsteriskJob for account #{@account_id}, inbox #{@inbox_id}, call #{unique_id}"
    ConversationFromAsteriskJob.perform_later(@account_id, @inbox_id, call_details)
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_new_channel_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_hangup_event(event)
    unique_id = event.attributes['Uniqueid']
    cause_txt = event.attributes['Cause-txt'] # Reason for hangup

    Rails.logger.info "AsteriskService: Hangup event received. UniqueID: #{unique_id}, Cause: #{cause_txt}"

    # Placeholder for any logic needed on call hangup, e.g.:
    # - Update conversation status (if it's tracked beyond the initial message)
    # - Log call duration if 'AMAFlags' or similar billing/duration info is available and relevant
    # Conversation.find_by('additional_attributes @> ?', { asterisk_unique_id: unique_id }.to_json)&.update(status: :resolved)
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_hangup_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # Method to initiate an outgoing call
  def originate_call(destination_number, caller_id_number = nil, custom_context = nil, custom_extension = nil, custom_priority = nil)
    raise "Not connected to Asterisk AMI" unless connected?
    raise "Destination number cannot be blank" if destination_number.blank?

    # Use channel settings as defaults
    # The `channel` object here is an instance of Channel::Asterisk
    caller_id = caller_id_number.presence || @channel.default_caller_id
    context = custom_context.presence || @channel.default_context
    extension = custom_extension.presence || @channel.default_extension # Often, for Originate, Exten is the number to dial if context routes it.
    priority = custom_priority.presence || @channel.default_priority

    # The originate_channel_string from the model should contain '{destination_number}'
    # Example: "SIP/your_provider/{destination_number}" or "PJSIP/{destination_number}@your_endpoint"
    channel_string_template = @channel.originate_channel_string
    unless channel_string_template.include?('{destination_number}')
      raise "originate_channel_string in Channel::Asterisk settings must include '{destination_number}' placeholder."
    end
    channel_to_dial = channel_string_template.gsub('{destination_number}', destination_number)

    action_params = {
      'Channel' => channel_to_dial,
      'Context' => context,
      'Exten' => extension, # This could be the destination number itself if the context is set up for direct dialing, or a specific extension.
      'Priority' => priority,
      'CallerID' => caller_id,
      'Async' => 'true', # Make the call asynchronous
      # 'Timeout' => 30000, # Optional: Timeout for the call attempt in milliseconds
      # 'Variable' => { 'variable1' => 'value1', 'variable2' => 'value2' } # Optional: Set variables for the call
    }

    Rails.logger.info "AsteriskService: Originating call to #{destination_number} via channel #{channel_to_dial} with params: #{action_params.except('Async')}"

    response = send_action('Originate', action_params)

    if response && response.success?
      Rails.logger.info "AsteriskService: Originate action successful. Response: #{response.message}"
    else
      error_message = response ? response.message : "No response from AMI"
      Rails.logger.error "AsteriskService: Originate action failed. Error: #{error_message}. Full response: #{response.inspect}"
      # Depending on desired behavior, you might raise an error here or return the failure response
      # raise "Originate failed: #{error_message}"
    end
    response # Return the full AMI response object
  end

  private

  def register_default_event_handlers
    register_event_handler('Newchannel', &method(:handle_new_channel_event))
    register_event_handler('Hangup', &method(:handle_hangup_event))
    register_event_handler('DialBegin', &method(:handle_dial_begin_event))
    register_event_handler('DialEnd', &method(:handle_dial_end_event))
    register_event_handler('BridgeEnter', &method(:handle_bridge_enter_event))
    register_event_handler('BridgeLeave', &method(:handle_bridge_leave_event))
    register_event_handler('VarSet', &method(:handle_var_set_event)) # For CDR recording file, etc.
    # Add more handlers as needed, e.g., for 'AgentCalled', 'AgentConnect', etc.
  end

  # Additional specific event handler methods
  def handle_dial_begin_event(event)
    unique_id = event.attributes['Uniqueid'] # The unique ID of the calling channel
    dest_unique_id = event.attributes['DestUniqueID'] # The unique ID of the dialed channel
    caller_id_num = event.attributes['CallerIDNum']
    dial_string = event.attributes['DialString'] # e.g., PJSIP/101 or SIP/provider/number

    Rails.logger.info "AsteriskService: DialBegin event. UniqueID: #{unique_id}, DestUniqueID: #{dest_unique_id}, CallerID: #{caller_id_num}, DialString: #{dial_string}"
    event_details = event.attributes.merge(event_name: event.name)
    UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, unique_id, event_details)
    # If the dest_unique_id is also relevant for tracking a specific leg, enqueue for it too,
    # though typically the source unique_id is the primary one for conversation lookup.
    # UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, dest_unique_id, event_details) if dest_unique_id.present?
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_dial_begin_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_dial_end_event(event)
    unique_id = event.attributes['Uniqueid']
    dest_unique_id = event.attributes['DestUniqueID']
    dial_status = event.attributes['DialStatus'] # e.g., ANSWER, BUSY, NOANSWER, CANCEL, CONGESTION

    Rails.logger.info "AsteriskService: DialEnd event. UniqueID: #{unique_id}, DestUniqueID: #{dest_unique_id}, Status: #{dial_status}"
    event_details = event.attributes.merge(event_name: event.name)
    UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, unique_id, event_details)
    # UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, dest_unique_id, event_details) if dest_unique_id.present?
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_dial_end_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_bridge_enter_event(event)
    # This event signifies two channels have been bridged (call connected)
    unique_id = event.attributes['Uniqueid'] # Often one of the channels in the bridge
    # BridgeUniqueid, BridgeType, BridgeTechnology, etc. might also be useful
    caller_id_num = event.attributes['CallerIDNum']
    connected_line_num = event.attributes['ConnectedLineNum'] # The other party in the bridge

    Rails.logger.info "AsteriskService: BridgeEnter event. UniqueID: #{unique_id}, CallerID: #{caller_id_num}, ConnectedLineNum: #{connected_line_num}"
    event_details = event.attributes.merge(event_name: event.name)
    # It's crucial to decide which UniqueID maps to your conversation.
    # If 'Uniqueid' is the one linked to the conversation:
    UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, unique_id, event_details)
    # Or, if the conversation is associated with the ConnectedLine's channel unique ID (less common for initial incoming):
    # UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, event.attributes['BridgeUniqueid'], event_details) # Example if BridgeUniqueid is the key
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_bridge_enter_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_bridge_leave_event(event)
    # Signifies a channel has left a bridge
    unique_id = event.attributes['Uniqueid']
    Rails.logger.info "AsteriskService: BridgeLeave event. UniqueID: #{unique_id}"
    event_details = event.attributes.merge(event_name: event.name)
    UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, unique_id, event_details)
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_bridge_leave_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def handle_var_set_event(event)
    variable_name = event.attributes['Variable']
    value = event.attributes['Value']
    unique_id = event.attributes['Uniqueid'] # Can be blank if variable is global

    # Only process if unique_id is present and it's a variable we care about
    return unless unique_id.present? && variable_name&.downcase == 'cdr(recordingfile)'

    Rails.logger.info "AsteriskService: VarSet event for recording. UniqueID: #{unique_id}, Variable: #{variable_name}, Value: #{value}"
    event_details = event.attributes.merge(event_name: event.name)
    UpdateAsteriskCallJob.perform_later(@account_id, @inbox_id, unique_id, event_details)
  rescue StandardError => e
    Rails.logger.error "AsteriskService: Error in handle_var_set_event: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def login
    # ruby-ami handles login implicitly during Stream.new if username/password are provided
    # and then .connect is called. We can check status or send a Ping.
    response = @ami_client.send_action(RubyAMI::Action.new('Ping'))
    if response && response.success?
      Rails.logger.info "AsteriskService: Successfully logged in and pinged AMI."
      return true
    else
      Rails.logger.error "AsteriskService: Failed to login/ping AMI. Response: #{response.inspect}"
      # Disconnect if login effectively failed
      @ami_client.disconnect
      @ami_client = nil
      raise "AsteriskService: AMI Login failed. Response: #{response.inspect}"
    end
  rescue RubyAMI::Error => e # Catch specific ruby-ami errors during login/ping
    Rails.logger.error "AsteriskService: AMI login/ping error: #{e.message}"
    @ami_client.disconnect if @ami_client&.connected?
    @ami_client = nil
    raise # Re-raise the exception
  end

  def start_event_listener
    return unless @ami_client

    @event_listener_thread = Thread.new do
      loop do
        break unless @ami_client&.connected?
        begin
          event = @ami_client.read_event(2) # Timeout for reading event
          next unless event # Timeout occurred

          Rails.logger.debug "AsteriskService: Received event: #{event.name} with attributes: #{event.attributes}"
          handle_event(event)
        rescue RubyAMI::ReadTimeout => e
          # This is expected if no events are coming in, continue loop
          next
        rescue RubyAMI::DisconnectedError => e
          Rails.logger.warn "AsteriskService: AMI disconnected while listening for events: #{e.message}"
          # Mark as disconnected and attempt reconnect or notify
          @ami_client = nil # Or some other state to indicate disconnection
          break # Exit listener thread
        rescue StandardError => e
          Rails.logger.error "AsteriskService: Error in event listener: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
          # Potentially break or attempt to recover depending on error
          sleep 1 # Avoid tight loop on persistent errors
        end
      end
      Rails.logger.info "AsteriskService: Event listener thread stopped."
    end
  end

  def stop_event_listener
    @event_listener_thread&.kill if @event_listener_thread&.alive?
    @event_listener_thread = nil
  end

  def handle_event(event)
    event_name = event.name.downcase
    if @event_handlers[event_name]
      @event_handlers[event_name].each do |handler|
        begin
          handler.call(event)
        rescue StandardError => e
          Rails.logger.error "AsteriskService: Error processing event handler for #{event_name}: #{e.message}"
        end
      end
    else
      # Rails.logger.debug "AsteriskService: No specific handler for event: #{event_name}"
    end
  end
end
