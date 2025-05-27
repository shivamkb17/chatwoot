class Api::V1::Accounts::Channels::AsteriskController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_inbox
  before_action :ensure_asterisk_channel

  # POST /api/v1/accounts/{account_id}/inboxes/{inbox_id}/asterisk/originate_call
  def originate_call
    destination_number = params.require(:destination_number)
    # Optional parameters
    caller_id_number = params[:caller_id_number]
    custom_context = params[:custom_context]
    custom_extension = params[:custom_extension]
    custom_priority = params[:custom_priority]

    asterisk_service = AsteriskService.new(@channel)

    unless asterisk_service.connect
      return render json: { error: 'Failed to connect to Asterisk AMI' }, status: :service_unavailable
    end

    ami_response = asterisk_service.originate_call(
      destination_number,
      caller_id_number,
      custom_context,
      custom_extension,
      custom_priority
    )

    if ami_response&.success?
      render json: { success: true, message: 'Call originated successfully.', data: ami_response.attributes }, status: :ok
    else
      error_message = ami_response ? ami_response.message : 'Originate action failed or no response from AMI.'
      render json: { success: false, error: error_message, data: ami_response&.attributes }, status: :bad_request
    end
  rescue StandardError => e
    Rails.logger.error "AsteriskController#originate_call error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { success: false, error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  ensure
    asterisk_service&.disconnect if asterisk_service&.connected?
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def ensure_asterisk_channel
    unless @inbox.channel.is_a?(Channel::Asterisk)
      render json: { error: 'The specified inbox is not configured for Asterisk.' }, status: :unprocessable_entity
      return
    end
    @channel = @inbox.channel
  end

  def check_authorization
    # Ensures that the current user (agent) has access to the inbox.
    # The specific pundit policy would be :show? or a more specific one like :perform_call_actions?
    authorize @inbox || Inbox, :show? # Or a more specific policy like :manage_asterisk_calls?
  end
end
