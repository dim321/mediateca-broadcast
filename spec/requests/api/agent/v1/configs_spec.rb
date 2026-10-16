# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Agent::V1::Configs', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  describe 'GET /api/agent/v1/config' do
    it 'returns this station cache policy and screens' do
      token = SecureRandom.hex(16)
      station = create(:station, offline_cache_hours: 48)
      station.assign_agent_token!(token)
      screen = create(:screen, station:, orientation: :portrait)

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

    it "returns tv_monitor only when the station has settings" do
      token = SecureRandom.hex(16)
      station = create(:station)
      station.assign_agent_token!(token)
      create(:station_tv_monitor, station:, health_interval_seconds: 30,
        auto_restart_when_not_playing: true, telemetry_interval_seconds: 60)

      get "/api/agent/v1/config", headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["tv_monitor"]).to eq(
        "health_interval_seconds" => 30,
        "auto_restart_when_not_playing" => true,
        "telemetry_interval_seconds" => 60
      )
    end

    it 'returns 401 for an invalid agent token' do
      get '/api/agent/v1/config', headers: agent_authorization_headers('invalid'), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns wiring fields for a networked screen and leaves a dark screen unchanged" do
      travel_to(wiring_time) do
        token = SecureRandom.hex(16)
        station = wiring_station
        station.assign_agent_token!(token)
        entrance = wired_screen(station, ip: "192.168.33.182", mac: "78:53:33:4b:2c:29", name: "Entrance")
        window = create(:screen, station:, name: "Window", orientation: :portrait)
        asset = create(:media_asset, :ready, :with_png_file)
        cover_horizon_with_slot(station, entrance, asset:)

        get "/api/agent/v1/config", headers: agent_authorization_headers(token), as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["screens"]).to eq([
          {
            "id" => entrance.id,
            "name" => "Entrance",
            "orientation" => "landscape",
            "adb_serial" => "192.168.33.182:5555",
            "mac" => "78:53:33:4b:2c:29",
            "stream_port" => 8091
          },
          {
            "id" => window.id,
            "name" => "Window",
            "orientation" => "portrait"
          }
        ])
      end
    end
  end
end
