class Channel::Asterisk < ApplicationRecord
  include Channelable

  # Attributes for Asterisk server details
  attribute :host, :string
  attribute :port, :integer
  attribute :username, :string
  attribute :password, :string
  attribute :webhook_url, :string

  # Attributes for outgoing calls
  attribute :default_caller_id, :string
  attribute :default_context, :string
  attribute :default_extension, :string # Often the destination number itself or a special setup extension
  attribute :default_priority, :integer, default: 1
  attribute :originate_channel_string, :string # e.g., "SIP/your_provider/{destination_number}" or "PJSIP/{destination_number}@your_endpoint"

  # Define editable attributes
  EDITABLE_ATTRS = [
    :host, :port, :username, :password, :webhook_url,
    :default_caller_id, :default_context, :default_extension,
    :default_priority, :originate_channel_string
  ].freeze

  # Validations
  validates :host, presence: true
  validates :port, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :username, presence: true
  validates :password, presence: true
  validates :webhook_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  # Validations for outgoing call attributes
  validates :default_caller_id, presence: true
  validates :default_context, presence: true
  validates :default_extension, presence: true # This is the 'Exten' for Originate if no specific one is given
  validates :default_priority, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :originate_channel_string, presence: true,
                                       format: { with: /{destination_number}/,
                                                 message: "must include '{destination_number}' placeholder" }


  # Channel name
  def name
    'Asterisk'
  end
end
