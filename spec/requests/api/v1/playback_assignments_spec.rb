# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::PlaybackAssignments", type: :request do
  describe "GET /api/v1/playback_assignments/current" do
    it "returns current assignment payload" do
      token = SecureRandom.hex(16)
      organization = create(:organization)
      point = create(:broadcast_point, organization:, device_token_digest: BCrypt::Password.create(token))
      group = create(:point_group, organization:)
      create(:point_group_membership, point_group: group, broadcast_point: point)

      playlist = create(:playlist, organization:)
      media_asset = create(:media_asset, :ready, :with_png_file, organization:)
      create(:playlist_item, playlist:, media_asset:, position: 1)
      create(
        :schedule_rule,
        organization:,
        playlist:,
        point_group: group,
        starts_at: 30.minutes.ago,
        ends_at: 30.minutes.from_now
      )

      get "/api/v1/playback_assignments/current", headers: device_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("assignment_id", "starts_at", "ends_at", "playlist")
      expect(response.parsed_body.dig("playlist", "id")).to eq(playlist.id)
      expect(response.parsed_body.dig("playlist", "items")).to include(
        include("position" => 1, "kind" => media_asset.content_kind)
      )
    end

    it "returns 204 when no assignment exists" do
      token = SecureRandom.hex(16)
      create(:broadcast_point, device_token_digest: BCrypt::Password.create(token))

      get "/api/v1/playback_assignments/current", headers: device_authorization_headers(token), as: :json

      expect(response).to have_http_status(:no_content)
    end

    it "returns 401 for invalid token" do
      get "/api/v1/playback_assignments/current", headers: device_authorization_headers("invalid"), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
