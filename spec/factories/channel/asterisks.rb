FactoryBot.define do
  factory :channel_asterisk, class: 'Channel::Asterisk' do
    account
    name { 'Asterisk Channel' } # Default name for the inbox that will be created
    host { 'asterisk.example.com' }
    port { 5038 }
    username { 'chatwoot_ami' }
    password { 'secure_password' }
    webhook_url { "https://chatwoot.example.com/webhooks/asterisk/#{SecureRandom.hex}" }

    # Attributes for outgoing calls
    default_caller_id { 'ChatwootCall' }
    default_context { 'from-chatwoot' }
    default_extension { 's' } # A generic default extension
    default_priority { 1 }
    # Ensure the placeholder is present for validation
    originate_channel_string { "PJSIP/{destination_number}@chatwoot_trunk" }

    after(:build) do |channel_asterisk|
      # Create an inbox associated with this channel
      # The inbox name can be derived from the channel or set explicitly
      inbox = build(:inbox, name: channel_asterisk.name, channel: channel_asterisk, account: channel_asterisk.account)
      # To avoid validation errors if Inbox requires channel to be saved first,
      # or if channel requires inbox_id.
      # This setup assumes Inbox doesn't immediately need the channel to be saved.
      # If channel.save is called, inbox.save should also be called.
      # For now, just associating it.
      channel_asterisk.inbox = inbox
    end
  end
end
