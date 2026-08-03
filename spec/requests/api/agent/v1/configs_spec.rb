# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Agent::V1::Configs', type: :request do
  describe 'GET /api/agent/v1/config' do
    it 'returns this station cache policy and screens' do
      token = SecureRandom.hex(16)
      station = create(:station, offline_cache_hours: 48)
      station.assign_agent_token!(token)
      screen = create(:screen, organization: station.organization, station:, orientation: :portrait)

      get '/api/agent/v1/config', headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'station_id' => station.id,
        'offline_cache_hours' => 48,
        'screens' => [
          {
            'id' => screen.id,
            'name' => screen.name,
            'orientation' => 'portrait'
          }
        ]
      )
    end

    it 'returns 401 for an invalid agent token' do
      get '/api/agent/v1/config', headers: agent_authorization_headers('invalid'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
