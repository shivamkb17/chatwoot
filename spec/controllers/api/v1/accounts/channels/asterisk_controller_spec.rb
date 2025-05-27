require 'rails_helper'

RSpec.describe Api::V1::Accounts::Channels::AsteriskController, type: :controller do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) } # Assuming agent role
  let!(:asterisk_channel) { create(:channel_asterisk, account: account) }
  let!(:inbox) { asterisk_channel.inbox }

  let(:asterisk_service_double) { instance_double(AsteriskService) }
  let(:ami_success_response) { RubyAMI::Response.new({ 'Message' => 'Call Originated', 'UniqueID' => '12345.6789' }, true) }
  let(:ami_failure_response) { RubyAMI::Response.new({ 'Message' => 'Originate Failed' }, false) }


  before do
    # Mock AsteriskService instantiation and methods
    allow(AsteriskService).to receive(:new).with(asterisk_channel).and_return(asterisk_service_double)
    allow(asterisk_service_double).to receive(:connect).and_return(true) # Default to successful connection
    allow(asterisk_service_double).to receive(:connected?).and_return(true) # Assume connected after connect
    allow(asterisk_service_double).to receive(:disconnect)
    allow(asterisk_service_double).to receive(:originate_call).and_return(ami_success_response) # Default to successful call
  end

  describe 'POST #originate_call' do
    let(:destination_number) { '5551112222' }
    let(:valid_params) { { account_id: account.id, inbox_id: inbox.id, destination_number: destination_number } }

    context 'when authenticated as an agent with access to the inbox' do
      before do
        sign_in(agent)
        # Ensure agent has access to the inbox - this might be through team membership or direct assignment
        # For simplicity, we assume the agent has access if they are part of the account.
        # A more specific test might involve setting up InboxMember.
        create(:inbox_member, user: agent, inbox: inbox)
      end

      it 'calls AsteriskService with correct parameters' do
        expect(asterisk_service_double).to receive(:originate_call).with(
          destination_number, nil, nil, nil, nil
        ).and_return(ami_success_response)
        post :originate_call, params: valid_params, format: :json
      end

      it 'calls AsteriskService with all optional parameters if provided' do
        custom_params = {
          caller_id_number: '5553334444',
          custom_context: 'test-context',
          custom_extension: 'test-exten',
          custom_priority: '99'
        }
        expect(asterisk_service_double).to receive(:originate_call).with(
          destination_number,
          custom_params[:caller_id_number],
          custom_params[:custom_context],
          custom_params[:custom_extension],
          custom_params[:custom_priority]
        ).and_return(ami_success_response)
        post :originate_call, params: valid_params.merge(custom_params), format: :json
      end

      it 'returns 200 OK with success message on successful call' do
        post :originate_call, params: valid_params, format: :json
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('Call originated successfully.')
        expect(json_response['data']).to include('Message' => 'Call Originated', 'UniqueID' => '12345.6789')
      end

      it 'returns 400 Bad Request if AsteriskService originate_call fails' do
        allow(asterisk_service_double).to receive(:originate_call).and_return(ami_failure_response)
        post :originate_call, params: valid_params, format: :json
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Originate Failed')
      end

      it 'returns 503 Service Unavailable if AsteriskService connect fails' do
        allow(asterisk_service_double).to receive(:connect).and_return(false)
        post :originate_call, params: valid_params, format: :json
        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to connect to Asterisk AMI')
      end

      it 'ensures AsteriskService disconnect is called' do
        expect(asterisk_service_double).to receive(:disconnect)
        post :originate_call, params: valid_params, format: :json
      end

      context 'when destination_number is missing' do
        it 'returns 400 Bad Request' do
          post :originate_call, params: { account_id: account.id, inbox_id: inbox.id }, format: :json
          expect(response).to have_http_status(:bad_request) # Rails default for missing param
          # The error message structure might depend on how param presence is enforced (controller vs service)
          # If controller: JSON.parse(response.body)['error'] would contain "param is missing or the value is empty: destination_number"
          # The controller has `params.require(:destination_number)`
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to match(/param is missing or the value is empty: destination_number/)
        end
      end

      context 'when inbox is not an Asterisk channel' do
        let!(:non_asterisk_inbox) { create(:inbox, account: account) } # Default factory creates non-Asterisk channel
        before do
           create(:inbox_member, user: agent, inbox: non_asterisk_inbox)
        end

        it 'returns 422 Unprocessable Entity' do
          post :originate_call, params: { account_id: account.id, inbox_id: non_asterisk_inbox.id, destination_number: destination_number }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)
          json_response = JSON.parse(response.body)
          expect(json_response['error']).to eq('The specified inbox is not configured for Asterisk.')
        end
      end

      context 'when inbox is not found' do
        it 'returns 404 Not Found' do
          post :originate_call, params: { account_id: account.id, inbox_id: 'invalid-id', destination_number: destination_number }, format: :json
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when not authenticated' do
      it 'returns 401 Unauthorized' do
        post :originate_call, params: valid_params, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated agent does not have access to the inbox' do
      let(:another_inbox) { create(:inbox, account: account) } # Agent not a member of this by default
      before do
        sign_in(agent)
        # Agent is NOT made a member of `another_inbox` here.
      end

      it 'returns 404 Not Found (due to Pundit policy)' do
        # Pundit's `authorize` will typically raise an error that leads to a 403 or 404.
        # The `check_authorization` uses `authorize @inbox || Inbox, :show?`
        # If the inbox is found but agent is not authorized, Pundit::NotAuthorizedError is raised.
        # The default Rails handling for this (if not rescued) is often a 500 or a specific rescue_from.
        # Assuming a typical setup where NotAuthorizedError leads to 403/404.
        # If the inbox is simply not found for the current_account, it's a 404 from `find`.
        # Let's assume `fetch_inbox` finds it, but pundit denies.
        # To make this test more robust, we'd need to know how Pundit::NotAuthorizedError is handled.
        # For now, let's assume it results in :forbidden (403) if not rescued or :not_found (404) if rescued.
        # The current controller uses `authorize @inbox || Inbox, :show?`.
        # If the inbox is found by `Current.account.inboxes.find`, Pundit then checks show?.
        # If show? is false, it raises Pundit::NotAuthorizedError.
        # The ApplicationController usually has a rescue_from Pundit::NotAuthorizedError.
        # Let's assume a common rescue that returns 403 or 404.
        # Given the current setup, it's likely a 404 because `fetch_inbox` scopes to `Current.account.inboxes`.
        # If an agent from another account tried, that would be a 404.
        # If an agent from the same account but without inbox membership, Pundit would deny if policy is strict.

        # Test with an inbox agent is not part of
        other_asterisk_channel = create(:channel_asterisk, account: account, name: "Other Asterisk")
        other_asterisk_inbox = other_asterisk_channel.inbox
        # `agent` is not a member of `other_asterisk_inbox`

        post :originate_call, params: { account_id: account.id, inbox_id: other_asterisk_inbox.id, destination_number: destination_number }, format: :json
        expect(response).to have_http_status(:not_found) # Or :forbidden, depending on Pundit setup for failed authorization
      end
    end
  end
end
