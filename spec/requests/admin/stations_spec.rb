# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin stations", type: :request do
  include ActiveJob::TestHelper

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:location) { create(:location) }

  before { sign_in_as(operator) }

  it "creates a station without copying a portrait" do
    create(:broadcast_portrait, :default, name: "Grid")

    expect {
      post admin_stations_path, params: {
        station: { location_id: location.id, name: "Lobby", offline_cache_hours: 24 }
      }
    }.to change(Station, :count).by(1)

    station = Station.find_by!(name: "Lobby")
    expect(response).to redirect_to(admin_station_path(station))
    expect(BroadcastPortrait.where(screen_id: station.screens.select(:id))).to be_empty
  end

  it "enqueues GenerateForDateJob when force-regenerating playlists and redirects to show" do
    station = create(:station, location: location)

    expect {
      post regenerate_playlists_admin_station_path(station)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(admin_station_path(station))
  end

  it "renders the current playlist source_kind and offset on show" do
    station = create(:station, location: location)
    playlist = create(:playlist, station: station, for_date: Date.new(2026, 9, 2), status: "current")
    create(:playlist_item, playlist: playlist, offset_seconds: 90, source_kind: "filler", position: 1)

    get admin_station_path(station), params: { date: "2026-09-02" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("90")
    expect(response.body).to include(I18n.t("enums.playlist_item.source_kind.filler"))
  end

  it "does not render a portrait template select on new" do
    create(:broadcast_portrait, :default, name: "Grid")

    get new_admin_station_path

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("station_template_id")
  end

  it "updates the station name without a template field" do
    station = create(:station, location: location)

    patch admin_station_path(station), params: {
      station: { location_id: location.id, name: "Renamed", offline_cache_hours: 24 }
    }

    expect(response).to redirect_to(admin_station_path(station))
    expect(station.reload.name).to eq("Renamed")
  end
end
