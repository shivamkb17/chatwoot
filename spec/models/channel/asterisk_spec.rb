require 'rails_helper'

RSpec.describe Channel::Asterisk, type: :model do
  describe 'validations' do
    let(:account) { create(:account) }
    subject { build(:channel_asterisk, account: account) }

    context 'standard attributes' do
      it { is_expected.to validate_presence_of(:host) }
      it { is_expected.to validate_presence_of(:port) }
      it { is_expected.to validate_numericality_of(:port).only_integer.is_greater_than(0) }
      it { is_expected.to validate_presence_of(:username) }
      it { is_expected.to validate_presence_of(:password) }
      it { is_expected.to validate_presence_of(:webhook_url) }
      it {
        is_expected.to allow_values('http://example.com', 'https://example.com/webhook').for(:webhook_url)
      }
      it {
        is_expected.not_to allow_values('ftp://example.com', 'example.com').for(:webhook_url)
          .with_message(I18n.t('activerecord.errors.models.channel/asterisk.attributes.webhook_url.invalid_format'))
      }
    end

    context 'outgoing call attributes' do
      it { is_expected.to validate_presence_of(:default_caller_id) }
      it { is_expected.to validate_presence_of(:default_context) }
      it { is_expected.to validate_presence_of(:default_extension) }
      it { is_expected.to validate_presence_of(:default_priority) }
      it { is_expected.to validate_numericality_of(:default_priority).only_integer.is_greater_than_or_equal_to(1) }
      it { is_expected.to validate_presence_of(:originate_channel_string) }

      it 'validates originate_channel_string format for {destination_number} placeholder' do
        channel = build(:channel_asterisk, originate_channel_string: 'SIP/trunk_name/')
        expect(channel).not_to be_valid
        expect(channel.errors[:originate_channel_string]).to include("must include '{destination_number}' placeholder")

        channel.originate_channel_string = 'PJSIP/{destination_number}@endpoint'
        # Need to check other validations as well, so we call valid? on the subject
        # that has other fields correctly populated by factory.
        subject.originate_channel_string = 'PJSIP/{destination_number}@endpoint'
        expect(subject).to be_valid
      end
    end

    it 'is valid with valid attributes' do
      # The factory should produce a valid object
      expect(subject).to be_valid
    end

    it 'associates with an inbox after build' do
      # The factory callback should have built an inbox
      expect(subject.inbox).to be_present
      expect(subject.inbox).to be_a(Inbox)
      expect(subject.inbox.name).to eq(subject.name) # Assuming inbox name is set from channel name
    end
  end

  describe '#name' do
    it 'returns "Asterisk"' do
      channel = build(:channel_asterisk)
      expect(channel.name).to eq('Asterisk') # The method returns the type, not the inbox name
    end
  end

  describe 'EDITABLE_ATTRS' do
    it 'defines the correct editable attributes' do
      expected_attrs = [
        :host, :port, :username, :password, :webhook_url,
        :default_caller_id, :default_context, :default_extension,
        :default_priority, :originate_channel_string
      ].sort # Sort for consistent comparison

      # Ensure the class constant is accessed correctly
      actual_attrs = Channel::Asterisk::EDITABLE_ATTRS.sort
      expect(actual_attrs).to eq(expected_attrs)
    end
  end

  describe 'callbacks' do
    it 'creates an inbox before create' do
      # Test the callback that creates inbox
      # Subject from factory already builds an inbox. To test the callback,
      # we might need to build without the factory's after(:build) or save it.
      channel = FactoryBot.build(:channel_asterisk)
      # At this point, inbox is built but not saved.
      # The Channelable concern handles inbox creation usually in a before_create callback.
      # Let's save the channel and check if an inbox is created and associated.
      expect { channel.save! }.to change(Inbox, :count).by(1)
      expect(channel.inbox).to be_persisted
      expect(channel.inbox.name).to eq(channel.name) # Inbox name from factory is 'Asterisk Channel'
      expect(channel.inbox.account_id).to eq(channel.account_id)
    end
  end
end
