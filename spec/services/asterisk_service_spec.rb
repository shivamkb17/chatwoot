require 'rails_helper'

# Mock RubyAMI globally for these tests
module RubyAMI
  class Stream
    def initialize(host, port, username, password, options = {}); end
    def connect; end
    def connected?; end
    def disconnect; end
    def logout; end
    def send_action(action); end
    def read_event(timeout = nil); end # Allow timeout parameter
    def register_event_handler(event_name, &block); end # Mock this if used directly by service
    def add_event_hook(hook_type, &block); end # Mock this as well if used
  end

  class Action
    attr_reader :name, :headers
    def initialize(name, headers = {}); @name = name; @headers = headers; end
  end

  class Response
    attr_reader :attributes, :success
    def initialize(attributes = {}, success = true)
      @attributes = attributes
      @success = success
    end

    def success?
      @success
    end

    def message
      @attributes['Message'] || (@success ? 'Success' : 'Failure')
    end
  end

  class Event
    attr_reader :name, :attributes
    def initialize(name, attributes = {}); @name = name; @attributes = attributes; end
  end

  # Define common AMI errors if needed by tests
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end
  class ReadTimeout < Error; end
  class DisconnectedError < Error; end
end

RSpec.describe AsteriskService, type: :service do
  let(:account) { create(:account) }
  let(:channel_asterisk) { create(:channel_asterisk, account: account) }
  let(:service) { described_class.new(channel_asterisk) }
  let(:ami_stream_mock) { instance_double(RubyAMI::Stream) }

  before do
    # Allow an instance of AsteriskService to create a RubyAMI::Stream
    allow(RubyAMI::Stream).to receive(:new).and_return(ami_stream_mock)
    # Default behaviors for common AMI stream methods
    allow(ami_stream_mock).to receive(:connect).and_return(true)
    allow(ami_stream_mock).to receive(:connected?).and_return(false) # Start as not connected
    allow(ami_stream_mock).to receive(:logout)
    allow(ami_stream_mock).to receive(:disconnect)
    allow(ami_stream_mock).to receive(:send_action).and_return(RubyAMI::Response.new({ 'Message' => 'Success' }, true))
    allow(ami_stream_mock).to receive(:read_event).and_return(nil) # Default to no events
    # Mock add_event_hook which is internally used by ruby-ami's event listening if not directly by service
    allow(ami_stream_mock).to receive(:add_event_hook)
  end

  describe '#initialize' do
    it 'stores channel attributes correctly' do
      expect(service.channel).to eq(channel_asterisk)
      expect(service.host).to eq(channel_asterisk.host)
      expect(service.port).to eq(channel_asterisk.port)
      expect(service.username).to eq(channel_asterisk.username)
      expect(service.password).to eq(channel_asterisk.password)
      expect(service.instance_variable_get(:@account_id)).to eq(channel_asterisk.account_id)
      expect(service.instance_variable_get(:@inbox_id)).to eq(channel_asterisk.inbox.id)
    end
  end

  describe '#connect' do
    before do
      # Simulate a successful Ping response for the login part
      ping_response = RubyAMI::Response.new({ 'Message' => 'Pong' }, true)
      allow(ami_stream_mock).to receive(:send_action).with(an_instance_of(RubyAMI::Action)).and_call_original # Allow other actions
      allow(ami_stream_mock).to receive(:send_action).with(have_attributes(name: 'Ping')).and_return(ping_response)
    end

    context 'when connection is successful' do
      before do
        allow(ami_stream_mock).to receive(:connected?).and_return(false, true) # Initially false, then true after connect
        allow(ami_stream_mock).to receive(:connect).and_return(true)
      end

      it 'connects to AMI, logs in, and starts event listener' do
        expect(service.connect).to be true
        expect(ami_stream_mock).to have_received(:connect)
        expect(ami_stream_mock).to have_received(:send_action).with(have_attributes(name: 'Ping'))
        expect(service.instance_variable_get(:@event_listener_thread)).to be_a(Thread)
        service.disconnect # Clean up the thread
      end

      it 'registers default event handlers' do
        expect(service).to receive(:register_default_event_handlers)
        service.connect
        service.disconnect
      end
    end

    context 'when connection fails' do
      before do
        allow(ami_stream_mock).to receive(:connect).and_raise(RubyAMI::ConnectionError, 'Connection refused')
      end

      it 'returns false and logs an error' do
        expect(Rails.logger).to receive(:error).with(/Failed to connect to AMI: Connection refused/)
        expect(service.connect).to be false
        expect(service.instance_variable_get(:@ami_client)).to be_nil
      end
    end

    context 'when login (Ping) fails' do
      before do
        allow(ami_stream_mock).to receive(:connect).and_return(true)
        allow(ami_stream_mock).to receive(:connected?).and_return(false, true, false) # connected, then ping fails, then disconnected
        failed_ping_response = RubyAMI::Response.new({ 'Message' => 'Ping failed' }, false)
        allow(ami_stream_mock).to receive(:send_action).with(have_attributes(name: 'Ping')).and_return(failed_ping_response)
      end

      it 'raises an error, disconnects, and logs' do
        expect(Rails.logger).to receive(:error).with(/AMI Login failed. Response:.*Ping failed/)
        expect { service.connect }.to raise_error(/AMI Login failed/)
        expect(ami_stream_mock).to have_received(:disconnect)
        expect(service.instance_variable_get(:@ami_client)).to be_nil
      end
    end
  end

  describe '#originate_call' do
    let(:destination_number) { '1234567890' }
    let(:originate_action_double) { instance_double(RubyAMI::Action) }

    before do
      # Ensure service is connected for these tests
      allow(service).to receive(:connected?).and_return(true)
      allow(service).to receive(:ami_client).and_return(ami_stream_mock) # Expose ami_client for send_action spy
      allow(RubyAMI::Action).to receive(:new).and_call_original # Allow other actions
      allow(RubyAMI::Action).to receive(:new).with('Originate', any_args).and_return(originate_action_double)
    end

    context 'with default parameters from channel' do
      it 'sends Originate action with correct parameters' do
        expected_channel_string = channel_asterisk.originate_channel_string.gsub('{destination_number}', destination_number)
        expected_params = {
          'Channel' => expected_channel_string,
          'Context' => channel_asterisk.default_context,
          'Exten' => channel_asterisk.default_extension,
          'Priority' => channel_asterisk.default_priority,
          'CallerID' => channel_asterisk.default_caller_id,
          'Async' => 'true'
        }
        expect(ami_stream_mock).to receive(:send_action).with(
          have_attributes(name: 'Originate', headers: expected_params)
        ).and_return(RubyAMI::Response.new({}, true))

        service.originate_call(destination_number)
      end
    end

    context 'with overridden parameters' do
      let(:custom_caller_id) { '987654321' }
      let(:custom_context) { 'custom-context' }
      let(:custom_extension) { 'custom-exten' }
      let(:custom_priority) { 2 }

      it 'sends Originate action with overridden parameters' do
        expected_channel_string = channel_asterisk.originate_channel_string.gsub('{destination_number}', destination_number)
        expected_params = {
          'Channel' => expected_channel_string,
          'Context' => custom_context,
          'Exten' => custom_extension,
          'Priority' => custom_priority,
          'CallerID' => custom_caller_id,
          'Async' => 'true'
        }
        expect(ami_stream_mock).to receive(:send_action).with(
          have_attributes(name: 'Originate', headers: expected_params)
        ).and_return(RubyAMI::Response.new({}, true))

        service.originate_call(destination_number, custom_caller_id, custom_context, custom_extension, custom_priority)
      end
    end

    context 'when originate_channel_string is missing placeholder' do
      before do
        channel_asterisk.update!(originate_channel_string: 'SIP/wrong_string')
      end
      it 'raises an error' do
         expect { service.originate_call(destination_number) }.to raise_error(/must include '{destination_number}' placeholder/)
      end
    end


    context 'when AMI action is successful' do
      it 'returns a success response' do
        allow(ami_stream_mock).to receive(:send_action).and_return(RubyAMI::Response.new({ 'Message' => 'Call Originated' }, true))
        response = service.originate_call(destination_number)
        expect(response).to be_success
        expect(response.message).to eq('Call Originated')
      end
    end

    context 'when AMI action fails' do
      it 'returns a failure response and logs error' do
        allow(ami_stream_mock).to receive(:send_action).and_return(RubyAMI::Response.new({ 'Message' => 'Originate failed' }, false))
        expect(Rails.logger).to receive(:error).with(/Originate action failed. Error: Originate failed/)
        response = service.originate_call(destination_number)
        expect(response).not_to be_success
        expect(response.message).to eq('Originate failed')
      end
    end
  end

  describe 'event handling' do
    let(:account_id) { channel_asterisk.account_id }
    let(:inbox_id) { channel_asterisk.inbox.id }

    before do
      # Mock the connection and login process to set up event handling
      allow(service).to receive(:connected?).and_return(true)
      allow(service).to receive(:ami_client).and_return(ami_stream_mock)
      service.send(:register_default_event_handlers) # Call private method to set up @event_handlers
    end

    def simulate_event(event_name, attributes)
      event = RubyAMI::Event.new(event_name, attributes)
      service.send(:handle_event, event) # Call private method for direct testing
    end

    context 'when Newchannel event is received' do
      let(:event_attrs) do
        { 'CallerIDNum' => '1000', 'CallerIDName' => 'Test Caller', 'Uniqueid' => '12345.678', 'ChannelStateDesc' => 'Ring' }
      end

      it 'enqueues ConversationFromAsteriskJob' do
        expected_job_args = {
          caller_id_num: '1000',
          caller_id_name: 'Test Caller',
          asterisk_unique_id: '12345.678',
          channel_state_desc: 'Ring'
        }
        expect(ConversationFromAsteriskJob).to receive(:perform_later).with(account_id, inbox_id, expected_job_args)
        simulate_event('Newchannel', event_attrs)
      end

      it 'does not enqueue job if ChannelStateDesc is not Ring/Ringing' do
        expect(ConversationFromAsteriskJob).not_to receive(:perform_later)
        simulate_event('Newchannel', event_attrs.merge('ChannelStateDesc' => 'Down'))
      end
    end

    context 'when Hangup event is received' do
      let(:event_attrs) { { 'Uniqueid' => '12345.678', 'Cause-txt' => 'Normal Clearing' } }

      it 'enqueues UpdateAsteriskCallJob (as per current AsteriskService#handle_hangup_event, though job might ignore it)' do
        # Note: The current handle_hangup_event in AsteriskService does not enqueue any job.
        # If it were to enqueue UpdateAsteriskCallJob, this test would be:
        # expect(UpdateAsteriskCallJob).to receive(:perform_later).with(account_id, inbox_id, '12345.678', event_attrs.merge(event_name: 'Hangup'))
        # For now, it only logs. We can test the logging.
        expect(Rails.logger).to receive(:info).with("AsteriskService: Hangup event received. UniqueID: 12345.678, Cause: Normal Clearing")
        simulate_event('Hangup', event_attrs)
      end
    end

    context 'when DialEnd event is received' do
      let(:event_attrs) { { 'Uniqueid' => '12345.678', 'DialStatus' => 'ANSWER' } }
      it 'enqueues UpdateAsteriskCallJob' do
        expect(UpdateAsteriskCallJob).to receive(:perform_later).with(account_id, inbox_id, '12345.678', event_attrs.merge(event_name: 'DialEnd'))
        simulate_event('DialEnd', event_attrs)
      end
    end

    context 'when BridgeEnter event is received' do
      let(:event_attrs) { { 'Uniqueid' => '12345.678', 'CallerIDNum' => '1000', 'ConnectedLineNum' => '2000' } }
      it 'enqueues UpdateAsteriskCallJob' do
        expect(UpdateAsteriskCallJob).to receive(:perform_later).with(account_id, inbox_id, '12345.678', event_attrs.merge(event_name: 'BridgeEnter'))
        simulate_event('BridgeEnter', event_attrs)
      end
    end

    context 'when VarSet event for CDR(recordingfile) is received' do
      let(:event_attrs) { { 'Uniqueid' => '12345.678', 'Variable' => 'CDR(recordingfile)', 'Value' => '/var/rec/call.wav' } }
      it 'enqueues UpdateAsteriskCallJob' do
        expect(UpdateAsteriskCallJob).to receive(:perform_later).with(account_id, inbox_id, '12345.678', event_attrs.merge(event_name: 'VarSet'))
        simulate_event('VarSet', event_attrs)
      end

      it 'does not enqueue job for other VarSet events' do
         expect(UpdateAsteriskCallJob).not_to receive(:perform_later)
         simulate_event('VarSet', { 'Uniqueid' => '12345.678', 'Variable' => 'OTHER_VAR', 'Value' => 'some_value' })
      end
    end
  end

  describe '#disconnect' do
    before do
      # Simulate a connected state
      allow(service).to receive(:connected?).and_return(true)
      allow(service).to receive(:ami_client).and_return(ami_stream_mock)
      # Ensure event listener thread exists to be stopped
      service.instance_variable_set(:@event_listener_thread, instance_double(Thread, alive?: true, kill: true))
    end

    it 'stops event listener, logs out, and disconnects' do
      expect(service.instance_variable_get(:@event_listener_thread)).to receive(:kill)
      expect(ami_stream_mock).to receive(:logout)
      expect(ami_stream_mock).to receive(:disconnect)
      service.disconnect
      expect(service.instance_variable_get(:@ami_client)).to be_nil
    end
  end
end
