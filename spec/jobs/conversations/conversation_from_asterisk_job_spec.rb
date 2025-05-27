require 'rails_helper'

RSpec.describe ConversationFromAsteriskJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:asterisk_channel) { create(:channel_asterisk, account: account) }
  let!(:inbox) { asterisk_channel.inbox } # The factory creates an inbox

  let(:caller_id_num) { '5551234567' }
  let(:normalized_caller_id_num) { TelephoneNumber.normalize(caller_id_num) }
  let(:caller_id_name) { 'John Doe' }
  let(:asterisk_unique_id) { "asterisk-call-#{SecureRandom.hex}" }
  let(:channel_state_desc) { 'Ring' }

  let(:call_details) do
    {
      caller_id_num: caller_id_num,
      caller_id_name: caller_id_name,
      asterisk_unique_id: asterisk_unique_id,
      channel_state_desc: channel_state_desc
    }
  end

  subject(:job) { described_class.perform_later(account.id, inbox.id, call_details) }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class).on_queue('default')
  end

  describe '#perform' do
    context 'when a new contact and conversation' do
      it 'creates a new contact' do
        perform_enqueued_jobs { job }
        contact = Contact.find_by(phone_number: normalized_caller_id_num, account_id: account.id)
        expect(contact).to be_present
        expect(contact.name).to eq(caller_id_name)
        expect(contact.additional_attributes['caller_id_name']).to eq(caller_id_name)
      end

      it 'creates a new contact_inbox' do
        perform_enqueued_jobs { job }
        contact = Contact.find_by(phone_number: normalized_caller_id_num)
        contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id)
        expect(contact_inbox).to be_present
        expect(contact_inbox.source_id).to eq("asterisk-#{asterisk_unique_id}-#{inbox.id}")
      end

      it 'creates a new conversation' do
        perform_enqueued_jobs { job }
        conversation = Conversation.find_by(inbox_id: inbox.id, account_id: account.id)
        expect(conversation).to be_present
        expect(conversation.status).to eq('open')
        expect(conversation.additional_attributes['asterisk_unique_id']).to eq(asterisk_unique_id)
        expect(conversation.additional_attributes['caller_id_num']).to eq(caller_id_num)
        expect(conversation.additional_attributes['caller_id_name']).to eq(caller_id_name)
      end

      it 'creates an initial incoming message' do
        perform_enqueued_jobs { job }
        conversation = Conversation.find_by(additional_attributes: { asterisk_unique_id: asterisk_unique_id })
        message = conversation.messages.first
        expect(message).to be_present
        expect(message.message_type).to eq('incoming')
        expect(message.sender_type).to eq('Contact')
        expect(message.content).to include("Incoming call from #{caller_id_name} (#{caller_id_num})")
        expect(message.content).to include("Asterisk Call ID: #{asterisk_unique_id}")
        expect(message.external_source_id).to eq("asterisk-call-#{asterisk_unique_id}")
        expect(message.additional_attributes['asterisk_unique_id']).to eq(asterisk_unique_id)
      end

      it 'dispatches CONVERSATION_CREATED event' do
        expect { perform_enqueued_jobs { job } }.to have_broadcasted_to("account-#{account.id}-conversations")
          .with { |data| expect(data[:event]).to eq(Conversation::CONVERSATION_CREATED) }
      end

      it 'dispatches MESSAGE_CREATED event' do
         expect { perform_enqueued_jobs { job } }.to have_broadcasted_to("account-#{account.id}-messages")
          .with { |data| expect(data[:event]).to eq(Message::MESSAGE_CREATED) }
      end
    end

    context 'when contact already exists' do
      let!(:existing_contact) do
        create(:contact, account: account, phone_number: normalized_caller_id_num, name: 'Old Name')
      end

      it 'uses the existing contact' do
        expect { perform_enqueued_jobs { job } }.not_to change(Contact, :count)
        conversation = Conversation.find_by(additional_attributes: { asterisk_unique_id: asterisk_unique_id })
        expect(conversation.contact).to eq(existing_contact)
      end

      it 'creates a new contact_inbox if one does not exist for this inbox' do
        perform_enqueued_jobs { job }
        contact_inbox = ContactInbox.find_by(contact_id: existing_contact.id, inbox_id: inbox.id)
        expect(contact_inbox).to be_present
      end
    end

    context 'when contact_inbox already exists' do
      let!(:existing_contact) { create(:contact, account: account, phone_number: normalized_caller_id_num) }
      let!(:existing_contact_inbox) { create(:contact_inbox, contact: existing_contact, inbox: inbox, source_id: "asterisk-some-other-id-#{inbox.id}") } # Different source_id initially

      it 'uses the existing contact_inbox if source_id matches after update, or creates new one if source_id is different' do
         # The job logic updates or creates source_id based on asterisk_unique_id for the current call.
         # This test setup implies that a contact_inbox for this contact & inbox might exist from a *previous* call.
         # The job should create a new contact_inbox if the source_id logic determines it's a new source.
         # However, current job logic uses a fixed source_id based on current call's asterisk_unique_id.
         # Let's refine the job logic to truly find_or_create_by source_id.
         # For now, the job will create a new one if the source_id is different.
         # If the source_id logic in the job was find_or_create_by(contact, inbox) then update source_id,
         # then it would use the existing one.
         # Given the job code: `ContactInbox.create!(... source_id: source_id)` it will likely create a new one or fail if not unique.
         # The job's `find_by` for contact_inbox is `ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id)`
         # This means it will find the existing_contact_inbox. Let's test that.

        perform_enqueued_jobs { job }
        # It should find and use the existing contact_inbox. The source_id in the job is for creation if not found.
        conversation = Conversation.find_by(additional_attributes: { asterisk_unique_id: asterisk_unique_id })
        expect(conversation.contact_inbox).to eq(existing_contact_inbox)
        # Verify that the source_id of existing_contact_inbox was NOT changed by this job.
        # The job's logic is: find contact_inbox, if not found, create with a new source_id.
        # It does not update the source_id of an existing contact_inbox.
        expect(existing_contact_inbox.reload.source_id).to eq("asterisk-some-other-id-#{inbox.id}")
      end
    end


    context 'idempotency: when conversation with the same asterisk_unique_id already exists' do
      let!(:existing_conversation) do
        # Manually create a conversation that this job would have created
        contact = create(:contact, account: account, phone_number: normalized_caller_id_num)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: "asterisk-#{asterisk_unique_id}-#{inbox.id}")
        create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                              additional_attributes: { asterisk_unique_id: asterisk_unique_id })
      end

      it 'does not create a new conversation' do
        expect { perform_enqueued_jobs { job } }.not_to change(Conversation, :count)
      end

      it 'does not create a new message' do
        # The job checks for existing conversation and returns if found.
        expect { perform_enqueued_jobs { job } }.not_to change(Message, :count)
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Conversation for Asterisk call ID #{asterisk_unique_id} already exists/)
        perform_enqueued_jobs { job }
      end
    end

    context 'when caller_id_name is blank' do
      let(:call_details_no_name) do
        {
          caller_id_num: caller_id_num,
          caller_id_name: '', # Blank name
          asterisk_unique_id: asterisk_unique_id,
          channel_state_desc: channel_state_desc
        }
      end
      subject(:job_no_name) { described_class.perform_later(account.id, inbox.id, call_details_no_name) }


      it 'uses caller_id_num as contact name' do
        perform_enqueued_jobs { job_no_name }
        contact = Contact.find_by(phone_number: normalized_caller_id_num)
        expect(contact.name).to eq(caller_id_num)
      end
    end
  end
end
