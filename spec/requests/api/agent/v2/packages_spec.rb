# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V2::Packages", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def create_day_playlist(station, screen, for_date:, asset:)
    playlist = create(
      :playlist,
      station: station,
      for_date: for_date,
      broadcast_day_starts_at: Time.utc(for_date.year, for_date.month, for_date.day, 2, 0, 0),
      generated_at: Time.current
    )
    create(
      :playlist_item,
      playlist: playlist,
      media_asset: asset,
      position: 1,
      offset_seconds: 0,
      duration_seconds: 10,
      source_kind: "filler"
    ).tap do |item|
      item.screens = [ screen ]
      item.save!
    end
  end

  describe "GET /api/agent/v2/package" do
    around do |example|
      travel_to(Time.utc(2026, 9, 2, 18, 0, 0), &example)
    end

    it "returns timed entries from today and tomorrow and leaves v1 as overlapping plans (AE9)" do
      client = create(:organization, :client)
      location = create(:location, time_zone: "UTC")
      station = create(:station, location: location, offline_cache_hours: 24)
      screen = create(:screen, station: station)
      token = station.assign_agent_token!
      today_asset = create(:media_asset, :ready, :with_png_file)
      tomorrow_asset = create(:media_asset, :ready, :with_png_file)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), asset: today_asset)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), asset: tomorrow_asset)

      rotation = create(:rotation, organization: client)
      plan_asset = create(:media_asset, :ready, :with_png_file, organization: client)
      create(:rotation_item, rotation: rotation, media_asset: plan_asset, position: 1)
      group = create(:broadcast_point_group, organization: client)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
      plan = create(
        :media_plan,
        organization: client,
        rotation: rotation,
        broadcast_point_group: group,
        starts_at: 1.hour.ago,
        ends_at: 2.hours.from_now
      )

      get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("private").and include("must-revalidate")
      expect(response.parsed_body["entries"].pluck("media").pluck("id")).to eq([ today_asset.id, tomorrow_asset.id ])

      get "/api/agent/v1/package", headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("items", "screen_map")
      expect(response.parsed_body["items"].pluck("media_plan_id")).to eq([ plan.id ])
    end

    it "returns empty entries and enqueues generate when there is no current playlist (AE10)" do
      location = create(:location, time_zone: "UTC")
      station = create(:station, location: location, offline_cache_hours: 24)
      token = station.assign_agent_token!

      expect {
        get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json
      }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["entries"]).to eq([])
      expect(response.parsed_body["screen_map"]).to eq({})
    end

    it "returns empty entries for a closed-day current playlist without falling back to v1 shape (AE10)" do
      location = create(:location, time_zone: "UTC")
      station = create(:station, location: location, offline_cache_hours: 24)
      create(:playlist, station: station, for_date: Date.new(2026, 9, 2), generated_at: Time.current)
      create(:playlist, station: station, for_date: Date.new(2026, 9, 3), generated_at: Time.current)
      token = station.assign_agent_token!

      get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["entries"]).to eq([])
      expect(response.parsed_body).not_to have_key("items")
    end

    it "returns 304 when If-None-Match matches the etag (AE11)" do
      location = create(:location, time_zone: "UTC")
      station = create(:station, location: location, offline_cache_hours: 24)
      screen = create(:screen, station: station)
      token = station.assign_agent_token!
      asset = create(:media_asset, :ready, :with_png_file)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), asset: asset)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), asset: asset)

      get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json
      etag = response.headers["ETag"]
      expect(response).to have_http_status(:ok)
      expect(etag).to be_present

      get "/api/agent/v2/package",
        headers: agent_authorization_headers(token).merge("If-None-Match" => etag),
        as: :json

      expect(response).to have_http_status(:not_modified)
    end

    it "returns 200 with a new body after the playlist etag changes (AE11)" do
      location = create(:location, time_zone: "UTC")
      station = create(:station, location: location, offline_cache_hours: 24)
      screen = create(:screen, station: station)
      token = station.assign_agent_token!
      first_asset = create(:media_asset, :ready, :with_png_file)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), asset: first_asset)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), asset: first_asset)

      get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json
      previous_etag = response.headers["ETag"]

      Playlist.current.where(station: station, for_date: Date.new(2026, 9, 2)).find_each do |playlist|
        playlist.items.destroy_all
        playlist.update_columns(status: Playlist.statuses.fetch("superseded"))
      end
      replacement = create(:media_asset, :ready, :with_png_file)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), asset: replacement)

      get "/api/agent/v2/package",
        headers: agent_authorization_headers(token).merge("If-None-Match" => previous_etag),
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(previous_etag)
      expect(response.parsed_body["entries"].first.dig("media", "id")).to eq(replacement.id)
    end

    it "returns 401 without a valid agent token" do
      get "/api/agent/v2/package", as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "unauthorized")
    end
  end
end
