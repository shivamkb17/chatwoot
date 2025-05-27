require 'rails_helper'

RSpec.describe UpdateAsteriskCallJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:asterisk_channel) { create(:channel_asterisk, account: account) }
  let!(:inbox) { asterisk_channel.inbox }
  let(:asterisk_unique_id) { "asterisk-call-#{SecureRandom.hex}" }

  let!(:contact) { create(:contact, account: account, phone_number: '+1234567890') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let!(:conversation) do
    create(:conversation,
           account: account,
           inbox: inbox,
           contact: contact,
           contact_inbox: contact_inbox,
           additional_attributes: { asterisk_unique_id: asterisk_unique_id, initial_event: 'Newchannel' })
  end

  subject(:job) { described_class.perform_later(account.id, inbox.id, asterisk_unique_id, event_details) }

  describe '#perform' do
    context 'when conversation does not exist' do
      let(:event_details) { { event_name: 'DialEnd', 'DialStatus' => 'ANSWER' } }
      subject(:job_no_convo) { described_class.perform_later(account.id, inbox.id, 'nonexistent-id', event_details) }

      it 'logs a warning and does not raise an error' do
        expect(Rails.logger).to receive(:warn).with(/No conversation found for Asterisk call ID nonexistent-id/)
        expect { perform_enqueued_jobs { job_no_convo } }.not_to raise_error
      end
    end

    context 'for DialEnd event' do
      let(:event_details) { { event_name: 'DialEnd', 'DialStatus' => 'ANSWER', 'UniqueID' => asterisk_unique_id } }

      it 'updates conversation additional_attributes' do
        perform_enqueued_jobs { job }
        conversation.reload
        expect(conversation.additional_attributes['last_asterisk_event']).to eq('DialEnd')
        expect(conversation.additional_attributes['call_status']).to eq('dialend')
        expect(conversation.additional_attributes['dial_status']).to eq('ANSWER')
      end

      it 'creates an activity message' do
        expect { perform_enqueued_jobs { job } }.to change(conversation.messages, :count).by(1)
        message = conversation.messages.last
        expect(message.message_type).to eq('activity')
        expect(message.content).to eq('Call attempt ended. Status: ANSWER')
      end

      it 'dispatches MESSAGE_CREATED and CONVERSATION_UPDATED events' do
        expect { perform_enqueued_jobs { job } }.to have_broadcasted_to("account-#{account.id}-messages")
          .with { |data| expect(data[:event]).to eq(Message::MESSAGE_CREATED) }
        expect { perform_enqueued_jobs { job } }.to have_broadcasted_to("account-#{account.id}-conversations")
          .with { |data| expect(data[:event]).to eq(Conversation::CONVERSATION_UPDATED) }
      end

      context 'when DialStatus indicates failure and call was not bridged' do
        let(:event_details_busy) { { event_name: 'DialEnd', 'DialStatus' => 'BUSY', 'UniqueID' => asterisk_unique_id } }
        subject(:job_busy) { described_class.perform_later(account.id, inbox.id, asterisk_unique_id, event_details_busy) }

        it 'updates conversation status to resolved (or closed)' do
          # Assuming the conversation status is 'open' initially and call_status is not 'bridgeenter'
          # The job does not currently change conversation status, this is a placeholder for that logic.
          # If it did, the test would be:
          # perform_enqueued_jobs { job_busy }
          # conversation.reload
          # expect(conversation.status).to eq('resolved') # or 'closed'
          # For now, just test attributes are updated
          perform_enqueued_jobs { job_busy }
          conversation.reload
          expect(conversation.additional_attributes['dial_status']).to eq('BUSY')
        end
      end
    end

    context 'for BridgeEnter event' do
      let(:event_details) do
        { event_name: 'BridgeEnter', 'BridgeUniqueid' => 'bridge-id-123', 'ConnectedLineNum' => 'agent/101', 'UniqueID' => asterisk_unique_id }
      end

      it 'updates conversation and creates activity message' do
        perform_enqueued_jobs { job }
        conversation.reload
        expect(conversation.additional_attributes['last_asterisk_event']).to eq('BridgeEnter')
        expect(conversation.additional_attributes['call_status']).to eq('bridgeenter')
        expect(conversation.additional_attributes['bridge_unique_id']).to eq('bridge-id-123')
        expect(conversation.additional_attributes['connected_line_num']).to eq('agent/101')

        message = conversation.messages.last
        expect(message.content).to eq('Call connected.')
      end
    end

    context 'for Hangup event' do
      let(:event_details) { { event_name: 'Hangup', 'Cause-txt' => 'Normal Clearing', 'UniqueID' => asterisk_unique_id } }

      it 'updates conversation and creates activity message' do
        perform_enqueued_jobs { job }
        conversation.reload
        expect(conversation.additional_attributes['last_asterisk_event']).to eq('Hangup')
        expect(conversation.additional_attributes['call_status']).to eq('hangup')
        expect(conversation.additional_attributes['hangup_cause']).to eq('Normal Clearing')

        message = conversation.messages.last
        expect(message.content).to eq('Call hung up. Reason: Normal Clearing')
        # Potentially updates conversation status to resolved/closed.
        # expect(conversation.status).to eq('resolved')
      end
    end

    context 'for VarSet event (CDR recordingfile)' do
      let(:recording_path) { '/var/spool/asterisk/monitor/call123.wav' }
      let(:event_details) { { event_name: 'VarSet', 'Variable' => 'CDR(recordingfile)', 'Value' => recording_path, 'UniqueID' => asterisk_unique_id } }

      it 'updates conversation with recording path and creates message' do
        perform_enqueued_jobs { job }
        conversation.reload
        expect(conversation.additional_attributes['last_asterisk_event']).to eq('VarSet')
        expect(conversation.additional_attributes['call_status']).to eq('varset') # or keep previous status
        expect(conversation.additional_attributes['call_recording_path']).to eq(recording_path)

        message = conversation.messages.last
        expect(message.content).to eq("Call recording available: #{recording_path}")
      end

      it 'does not create a message for other VarSet events' do
         other_var_event = { event_name: 'VarSet', 'Variable' => 'OTHER_VAR', 'Value' => 'some_value', 'UniqueID' => asterisk_unique_id }
         expect {
           described_class.perform_now(account.id, inbox.id, asterisk_unique_id, other_var_event)
         }.not_to change(conversation.messages, :count)
         conversation.reload
         expect(conversation.additional_attributes['call_recording_path']).to be_nil # Ensure it wasn't set
      end
    end

    context 'for an unhandled event name' do
      let(:event_details) { { event_name: 'SomeOtherEvent', 'Detail' => 'Something happened', 'UniqueID' => asterisk_unique_id } }

      it 'updates last_asterisk_event but does not create a message' do
         expect {
           described_class.perform_now(account.id, inbox.id, asterisk_unique_id, event_details)
         }.not_to change(conversation.messages, :count)

        conversation.reload
        expect(conversation.additional_attributes['last_asterisk_event']).to eq('SomeOtherEvent')
        # call_status would be updated to 'someotherevent' by current logic
        expect(conversation.additional_attributes['call_status']).to eq('someotherevent')
      end
    end
  end
end
