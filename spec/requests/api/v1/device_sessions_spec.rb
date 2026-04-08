# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::DeviceSessions", type: :request do
  describe "POST /api/v1/device_sessions" do
    it "issues a device token for a valid pairing code" do
      point = create(:broadcast_point, venue_label: "PAIR-001")

      post "/api/v1/device_sessions", params: { pairing_code: "PAIR-001" }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["broadcast_point_id"]).to eq(point.id)
      expect(body["poll_interval_seconds"]).to eq(45)
      expect(body["device_token"]).to be_present

      expect(BCrypt::Password.new(point.reload.device_token_digest).is_password?(body["device_token"])).to eq(true)
    end

    it "returns 422 for invalid pairing code" do
      post "/api/v1/device_sessions", params: { pairing_code: "UNKNOWN" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("invalid_pairing_code")
    end

    it "returns 409 when point is already paired" do
      token = SecureRandom.hex(16)
      create(:broadcast_point, venue_label: "PAIR-LOCKED", device_token_digest: BCrypt::Password.create(token))

      post "/api/v1/device_sessions", params: { pairing_code: "PAIR-LOCKED" }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("already_paired")
    end
  end

  describe "GET /api/v1/device_sessions/current" do
    it "returns current broadcast point data for valid token" do
      token = SecureRandom.hex(16)
      organization = create(:organization, time_zone: "Europe/Moscow")
      point = create(
        :broadcast_point,
        organization:,
        time_zone: nil,
        device_token_digest: BCrypt::Password.create(token)
      )

      get "/api/v1/device_sessions/current", headers: device_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "broadcast_point_id" => point.id,
        "organization_id" => organization.id,
        "time_zone" => "Europe/Moscow",
        "poll_interval_seconds" => 45
      )
    end

    it "returns 401 for invalid token" do
      get "/api/v1/device_sessions/current", headers: device_authorization_headers("wrong-token"), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
