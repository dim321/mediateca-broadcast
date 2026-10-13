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

  it "shows the latest telemetry snapshot" do
    station = create(:station, location: location)
    screen = create(:screen, station:)
    StationTelemetrySnapshot.create!(
      station: station,
      reported_at: Time.utc(2026, 10, 9, 11, 0, 0),
      uptime_seconds: 3600,
      package_etag: "W/\"pkg\"",
      broadcast_ok: true,
      ignored_screen_ids: [ 404 ]
    )
    ScreenTelemetrySnapshot.create!(
      screen: screen,
      station: station,
      reported_at: Time.utc(2026, 10, 9, 11, 0, 0),
      reachable: true,
      agent_ok: true,
      playing: false,
      url: "http://192.168.33.1:8091/",
      wakefulness: "",
      stream_port: 8091,
      broadcast_clients: 0,
      last_error: "player down"
    )

    get admin_station_path(station)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("pkg")
    expect(response.body).to include("player down")
    expect(response.body).to include("404")
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

  it "creates tv monitor settings when the operator opts in on create" do
    expect {
      post admin_stations_path, params: {
        station: {
          location_id: location.id,
          name: "Monitor lobby",
          offline_cache_hours: 24,
          configure_tv_monitor: "1",
          tv_monitor: {
            health_interval_seconds: 20,
            auto_restart_when_not_playing: "1",
            telemetry_interval_seconds: 90
          }
        }
      }
    }.to change(Station, :count).by(1)

    station = Station.find_by!(name: "Monitor lobby")
    expect(response).to redirect_to(admin_station_path(station))
    monitor = station.tv_monitor
    expect(monitor.health_interval_seconds).to eq(20)
    expect(monitor.auto_restart_when_not_playing).to be(true)
    expect(monitor.telemetry_interval_seconds).to eq(90)
  end

  it "renders the new form again when telemetry interval is below 5 on create" do
    expect {
      post admin_stations_path, params: {
        station: {
          location_id: location.id,
          name: "Bad telemetry interval",
          offline_cache_hours: 24,
          configure_tv_monitor: "1",
          tv_monitor: {
            health_interval_seconds: 30,
            auto_restart_when_not_playing: "1",
            telemetry_interval_seconds: 4
          }
        }
      }
    }.not_to change(Station, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(Station.find_by(name: "Bad telemetry interval")).to be_nil
    station_form = Nokogiri::HTML(response.body).at_css("form[action='#{admin_stations_path}']")
    expect(station_form).to be_present
    expect(station_form.at_css("input[name='_method'][value='patch']")).to be_nil
  end

  it "does not create tv monitor settings unless the operator opts in" do
    post admin_stations_path, params: {
      station: {
        location_id: location.id,
        name: "Lobby",
        offline_cache_hours: 24,
        configure_tv_monitor: "0",
        tv_monitor: { health_interval_seconds: 30, auto_restart_when_not_playing: "1", telemetry_interval_seconds: 60 }
      }
    }

    station = Station.find_by!(name: "Lobby")
    expect(station.tv_monitor).to be_nil
  end

  it "saves an explicit false auto-restart when tv monitor is enabled" do
    station = create(:station, location: location)

    patch admin_station_path(station), params: {
      station: {
        location_id: location.id,
        name: station.name,
        offline_cache_hours: 24,
        configure_tv_monitor: "1",
        tv_monitor: {
          health_interval_seconds: 20,
          auto_restart_when_not_playing: "0",
          telemetry_interval_seconds: 90
        }
      }
    }

    expect(response).to redirect_to(admin_station_path(station))
    monitor = station.reload.tv_monitor
    expect(monitor.health_interval_seconds).to eq(20)
    expect(monitor.auto_restart_when_not_playing).to be(false)
    expect(monitor.telemetry_interval_seconds).to eq(90)
  end

  it "drops tv monitor settings when the operator clears the checkbox" do
    station = create(:station, location: location)
    create(:station_tv_monitor, station:)

    patch admin_station_path(station), params: {
      station: {
        location_id: location.id,
        name: station.name,
        offline_cache_hours: 24,
        configure_tv_monitor: "0"
      }
    }

    expect(station.reload.tv_monitor).to be_nil
  end

  it "renders the edit form again when the health interval is below 5" do
    station = create(:station, location: location)

    patch admin_station_path(station), params: {
      station: {
        location_id: location.id,
        name: station.name,
        offline_cache_hours: 24,
        configure_tv_monitor: "1",
        tv_monitor: {
          health_interval_seconds: 1,
          auto_restart_when_not_playing: "1",
          telemetry_interval_seconds: 60
        }
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(station.reload.tv_monitor).to be_nil
  end

  it "renders agent v2 package JSON on show" do
    station = create(:station, location: location)

    get admin_station_path(station)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.stations.agent_package_v2"))
    expect(response.body).to include("entries")
    expect(response.body).to include("screen_map")
    expect(response.body).to include("etag")
  end

  it "renders agent v1 config JSON on show" do
    station = create(:station, location: location)
    create(:screen, station: station, name: "Lobby TV", orientation: "landscape")

    get admin_station_path(station)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.stations.agent_config_v1"))
    expect(response.body).to include("station_id")
    expect(response.body).to include("screens")
    expect(response.body).to include("offline_cache_hours")
    expect(response.body).to include("Lobby TV")
  end

  it "enqueues GenerateForDateJob when show builds package with missing horizon playlists" do
    station = create(:station, location: location, offline_cache_hours: 24)

    expect {
      get admin_station_path(station)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

    expect(response).to have_http_status(:ok)
  end
end
