class UpdateAsteriskCallJob < ApplicationJob
  queue_as :default

  # Perform method to update conversation based on Asterisk event
  # account_id: ID of the account
  # inbox_id: ID of the inbox associated with the call
  # asterisk_unique_id: The UniqueID of the Asterisk channel/call leg
  # event_details: A hash containing event name and its attributes
  def perform(account_id, inbox_id, asterisk_unique_id, event_details)
    event_name = event_details['event_name'] || event_details[:event_name] # Handle string or symbol keys
    Rails.logger.info "UpdateAsteriskCallJob: Processing event '#{event_name}' for Asterisk call ID #{asterisk_unique_id} in account #{account_id}, inbox #{inbox_id}"
    Rails.logger.debug "UpdateAsteriskCallJob: Event details: #{event_details.inspect}"

    # Find the conversation using the asterisk_unique_id stored in additional_attributes
    # Note: We might need to search across multiple unique IDs if the conversation involves multiple legs (e.g., Uniqueid, DestUniqueID, BridgeUniqueID)
    # For simplicity, this example assumes asterisk_unique_id is the primary one linked to the conversation.
    conversation = Conversation.where(account_id: account_id, inbox_id: inbox_id)
                               .where("additional_attributes->>'asterisk_unique_id' = ?", asterisk_unique_id)
                               .first

    unless conversation
      Rails.logger.warn "UpdateAsteriskCallJob: No conversation found for Asterisk call ID #{asterisk_unique_id} in account #{account_id}, inbox #{inbox_id}. Event: #{event_name}"
      # Depending on the event, we might want to create a conversation if it's an early event like DialBegin from an *outgoing* call
      # For now, we'll only update existing conversations.
      return
    end

    ActiveRecord::Base.transaction do
      # Update conversation's additional_attributes with the latest call state
      # Store the last few event names or a more specific call status
      new_call_status = event_name.downcase
      updated_attrs = conversation.additional_attributes.merge(
        last_asterisk_event: event_name,
        call_status: new_call_status # Example: 'dialbegin', 'bridged', 'hangup'
      )

      message_content = nil
      message_type = :activity # Most call lifecycle events are activities

      case event_name.downcase
      when 'dialbegin'
        updated_attrs[:dial_string] = event_details['DialString'] || event_details[:dial_string]
        updated_attrs[:dial_dest_unique_id] = event_details['DestUniqueID'] || event_details[:dest_unique_id]
        message_content = "Call dialing to #{updated_attrs[:dial_string]}..."
      when 'dialend'
        updated_attrs[:dial_status] = event_details['DialStatus'] || event_details[:dial_status]
        message_content = "Call attempt ended. Status: #{updated_attrs[:dial_status]}"
        # Potentially close conversation if DialStatus indicates failure (BUSY, NOANSWER, etc.)
        # and the call was never bridged.
        if ['BUSY', 'NOANSWER', 'CONGESTION', 'CANCEL', 'CHANUNAVAIL'].include?(updated_attrs[:dial_status]) && conversation.additional_attributes['call_status'] != 'bridgeenter'
           # conversation.update!(status: :resolved) # Or :closed if that's the term
        end
      when 'bridgeenter'
        # Call is connected
        updated_attrs[:bridge_unique_id] = event_details['BridgeUniqueid'] || event_details[:bridge_unique_id]
        updated_attrs[:connected_line_num] = event_details['ConnectedLineNum'] || event_details[:connected_line_num]
        message_content = "Call connected."
        # Ensure conversation is open
        # conversation.update!(status: :open) if conversation.status != :open
      when 'bridgeleave'
        message_content = "Call disconnected from bridge."
        # This often precedes Hangup. The Hangup event handler might be better for closing.
      when 'hangup'
        # The ConversationFromAsteriskJob already creates a message for incoming calls.
        # This might be redundant or could provide more specific hangup info.
        # For outgoing calls, this is where we confirm it ended.
        updated_attrs[:hangup_cause] = event_details['Cause-txt'] || event_details[:cause_txt]
        message_content = "Call hung up. Reason: #{updated_attrs[:hangup_cause]}"
        # conversation.update!(status: :resolved) # Or :closed
      when 'varset'
        variable_name = event_details['Variable'] || event_details[:variable]
        value = event_details['Value'] || event_details[:value]
        if variable_name&.downcase == 'cdr(recordingfile)' && value.present?
          updated_attrs[:call_recording_path] = value
          message_content = "Call recording available: #{value}"
          # Here you might create an attachment message if the file is accessible via URL
          # For now, just logging it as an activity and storing in additional_attributes.
        else
          # Do not create a message for other VarSet events unless desired
          message_content = nil
        end
      else
        Rails.logger.info "UpdateAsteriskCallJob: No specific handling for event '#{event_name}'. Storing event in additional_attributes."
        # Store unhandled event details if necessary, or just the name as done above.
      end

      conversation.update!(additional_attributes: updated_attrs)
      Rails.logger.debug "UpdateAsteriskCallJob: Updated conversation #{conversation.id} attributes: #{updated_attrs}"

      # Create an activity message if content is set
      if message_content.present?
        message = conversation.messages.create!(
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: message_type,
          content: message_content,
          sender_type: nil, # System generated
          sender_id: nil    # System generated
        )
        Rails.logger.info "UpdateAsteriskCallJob: Created activity message ID #{message.id} for conversation #{conversation.id}"
        # Dispatch Action Cable event for the new message
        message.dispatch_event(Message::MESSAGE_CREATED)
      end

      # Dispatch Action Cable event for conversation update (e.g., for additional_attributes change)
      # This ensures UI reflects changes to call_status or other attributes if displayed.
      conversation.dispatch_event(Conversation::CONVERSATION_UPDATED)

    end # End of transaction

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "UpdateAsteriskCallJob: Conversation not found for Asterisk call ID #{asterisk_unique_id}. Error: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UpdateAsteriskCallJob: RecordInvalid error: #{e.message}. Details: #{e.record.errors.full_messages.join(', ')}"
    raise
  rescue StandardError => e
    Rails.logger.error "UpdateAsteriskCallJob: Error processing job for Asterisk call ID #{asterisk_unique_id}: #{e.message}\n#{e.backtrace.join("\n")}"
    raise
  end
end
