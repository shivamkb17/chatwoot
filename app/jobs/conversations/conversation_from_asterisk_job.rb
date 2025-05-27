class ConversationFromAsteriskJob < ApplicationJob
  queue_as :default

  def perform(account_id, inbox_id, call_details)
    Rails.logger.info "ConversationFromAsteriskJob: Received job for account #{account_id}, inbox #{inbox_id}, call: #{call_details.inspect}"

    account = Account.find(account_id)
    inbox = account.inboxes.find(inbox_id)
    caller_id_num = call_details[:caller_id_num]
    asterisk_unique_id = call_details[:asterisk_unique_id]

    # 1. Find or create Contact
    # Using phone_number as the primary identifier for Asterisk contacts.
    # Normalize phone number if necessary, e.g., by adding a '+' or country code if consistently missing.
    normalized_phone_number = TelephoneNumber.normalize(caller_id_num) # Example, use your preferred normalization
    contact_name = call_details[:caller_id_name].presence || caller_id_num

    ActiveRecord::Base.transaction do
      contact = Contact.find_by(account_id: account.id, phone_number: normalized_phone_number)
      unless contact
        contact = Contact.create!(
          account_id: account.id,
          name: contact_name,
          phone_number: normalized_phone_number,
          # Additional attributes can be set here if needed
          # email: nil, # if you don't have email
          additional_attributes: {
            caller_id_name: call_details[:caller_id_name]
          }
        )
        Rails.logger.info "ConversationFromAsteriskJob: Created new contact for #{caller_id_num}, ID: #{contact.id}"
      else
        Rails.logger.info "ConversationFromAsteriskJob: Found existing contact for #{caller_id_num}, ID: #{contact.id}"
      end

      # 2. Create ContactInbox
      contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id)
      unless contact_inbox
        # Ensure the source_id is unique for the contact_inbox if it's derived from contact info + inbox
        # For Asterisk, caller_id_num related to this inbox can be a source_id.
        # This might need to be more robust depending on how source_ids are generally used.
        # A combination of "asterisk-" + caller_id_num might be suitable.
        source_id = "asterisk-#{asterisk_unique_id}-#{inbox.id}" # Ensure uniqueness for this contact on this inbox

        contact_inbox = ContactInbox.create!(
          contact_id: contact.id,
          inbox_id: inbox.id,
          source_id: source_id # This ID should be unique for this contact on this inbox
        )
        Rails.logger.info "ConversationFromAsteriskJob: Created new contact_inbox for contact #{contact.id} and inbox #{inbox.id}, ID: #{contact_inbox.id}"
      else
        Rails.logger.info "ConversationFromAsteriskJob: Found existing contact_inbox for contact #{contact.id} and inbox #{inbox.id}, ID: #{contact_inbox.id}"
      end

      # 3. Create Conversation
      # Check if a conversation for this specific call already exists to prevent duplicates if events are re-processed
      existing_conversation = Conversation.find_by('additional_attributes @> ?', { asterisk_unique_id: asterisk_unique_id }.to_json)
      if existing_conversation
        Rails.logger.warn "ConversationFromAsteriskJob: Conversation for Asterisk call ID #{asterisk_unique_id} already exists (ID: #{existing_conversation.id}). Skipping creation."
        return
      end

      conversation = Conversation.create!(
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: contact.id,
        contact_inbox_id: contact_inbox.id,
        status: :open, # Or :pending, depending on workflow
        assignee_id: nil, # Auto-assignment can be handled by other mechanisms if configured
        additional_attributes: {
          asterisk_unique_id: asterisk_unique_id,
          caller_id_num: caller_id_num,
          caller_id_name: call_details[:caller_id_name],
          channel_state_desc: call_details[:channel_state_desc]
        }
      )
      Rails.logger.info "ConversationFromAsteriskJob: Created new conversation ID: #{conversation.id} for Asterisk call #{asterisk_unique_id}"

      # 4. Create an initial Message
      message_content = "Incoming call from #{contact_name} (#{caller_id_num}). Asterisk Call ID: #{asterisk_unique_id}"
      message = Message.create!(
        account_id: account.id,
        inbox_id: inbox.id,
        conversation_id: conversation.id,
        message_type: :incoming, # Or :activity if it's more of a system event
        sender_type: 'Contact',
        sender_id: contact.id,
        content: message_content,
        # external_source_id could be the asterisk_unique_id to link it directly to the call event on Asterisk
        # This helps in identifying the message related to this specific call event.
        external_source_id: "asterisk-call-#{asterisk_unique_id}",
        additional_attributes: {
          asterisk_unique_id: asterisk_unique_id
        }
      )
      Rails.logger.info "ConversationFromAsteriskJob: Created initial message ID: #{message.id} for conversation #{conversation.id}"

      # 5. Dispatch Action Cable event (placeholder for now)
      # Rails.logger.info "ConversationFromAsteriskJob: TODO: Dispatch Action Cable event for new conversation/message."
      # ConversationNotifications::CreateNotificationService.new(conversation: conversation).perform
      # Or more specific:
      # ::BroadcastNotificationsJob.perform_later(conversation, :conversation_created)
      # ::BroadcastNotificationsJob.perform_later(message, :message_created)

      # Dispatch events that the frontend listens to for new messages & conversations
      # This pattern is common in Chatwoot.
      conversation.dispatch_event(Conversation::CONVERSATION_CREATED)
      message.dispatch_event(Message::MESSAGE_CREATED)


    end # End of transaction
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "ConversationFromAsteriskJob: RecordInvalid error: #{e.message}. Details: #{e.record.errors.full_messages.join(', ')}"
    # Optionally, re-raise or handle specific retry logic if applicable
    raise
  rescue StandardError => e
    Rails.logger.error "ConversationFromAsteriskJob: Error processing job: #{e.message}\n#{e.backtrace.join("\n")}"
    # Optionally, re-raise or handle specific retry logic
    raise
  end
end
