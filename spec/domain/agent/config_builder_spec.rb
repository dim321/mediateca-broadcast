# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent::ConfigBuilder do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  describe '.call' do
    around do |example|
      travel_to(wiring_time) { example.run }
    end

    it 'builds cache policy and the station screen map' do
      station = create(:station, offline_cache_hours: 12)
      screen = create(:screen, station:)

      expect(described_class.call(station:)).to eq(
        station_id: station.id,
        offline_cache_hours: 12,
        screens: [
          {
            id: screen.id,
            name: screen.name,
            orientation: 'landscape'
          }
        ]
      )
    end

    it "omits tv_monitor when the station has no settings row" do
      station = create(:station)

      expect(described_class.call(station:)).not_to have_key(:tv_monitor)
    end

    it "includes an explicit auto-restart boolean when settings exist" do
      station = create(:station)
      create(:station_tv_monitor, station:, health_interval_seconds: 15,
        auto_restart_when_not_playing: false, telemetry_interval_seconds: 45)

      expect(described_class.call(station:)).to include(
        tv_monitor: {
          health_interval_seconds: 15,
          auto_restart_when_not_playing: false,
          telemetry_interval_seconds: 45
        }
      )
    end

    it "adds adb serial, canonical mac and a pool port for a wired screen with a timeline" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182", mac: "78-53-33-4B-2C-29", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen, asset:)

      payload = described_class.call(station:)

      expect(payload[:screens]).to eq([
        {
          id: screen.id,
          name: "Entrance",
          orientation: "landscape",
          adb_serial: "192.168.33.182:5555",
          mac: "78:53:33:4b:2c:29",
          stream_port: 8091
        }
      ])
    end

    it "strips an inet host prefix from the adb serial" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182")
      screen.update_columns(ip_address: "192.168.33.182/32")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen.reload, asset:)

      payload = described_class.call(station:)

      expect(payload[:screens].first[:adb_serial]).to eq("192.168.33.182:5555")
    end

    it "gives two screens with the same slots one port and splits different slots" do
      station = wiring_station
      shared_asset = create(:media_asset, :ready, :with_png_file)
      other_asset = create(:media_asset, :ready, :with_png_file)
      entrance = wired_screen(station, ip: "192.168.33.182", mac: "78:53:33:4b:2c:29", name: "Entrance")
      hall = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      window = wired_screen(station, ip: "192.168.33.184", mac: "78:53:33:4b:2c:31", name: "Window")
      cover_horizon(station).each do |playlist|
        add_slot(playlist, entrance, asset: shared_asset)
        add_slot(playlist, hall, asset: shared_asset)
        add_slot(playlist, window, asset: other_asset, offset_seconds: 30)
      end

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Entrance"][:stream_port]).to eq(screens["Hall"][:stream_port])
      expect(screens["Window"][:stream_port]).not_to eq(screens["Entrance"][:stream_port])
      expect(station.stream_channels.count).to eq(2)
    end

    it "keeps an unwired screen in the list with only identity fields" do
      station = wiring_station
      wired = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      dark = create(:screen, station:, name: "Window", network_registered: false, ip_address: nil, mac_address: nil)
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, wired, asset:)

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Window"]).to eq(id: dark.id, name: "Window", orientation: "landscape")
      expect(screens["Entrance"]).to have_key(:stream_port)
    end

    it "omits mac without a hardware address and omits the port for an empty timeline" do
      station = wiring_station
      silent = wired_screen(station, ip: "192.168.33.182", mac: nil, name: "Silent")
      cover_horizon(station)

      screen = described_class.call(station:)[:screens].first

      expect(screen[:adb_serial]).to eq("192.168.33.182:5555")
      expect(screen).not_to have_key(:mac)
      expect(screen).not_to have_key(:stream_port)
      expect(silent).to be_persisted
      expect(station.stream_channels).to be_empty
    end

    it "returns the same port on the second call and reuses it for a new screen with the known timeline" do
      station = wiring_station
      first = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, first, asset:)
      first_port = described_class.call(station:)[:screens].first[:stream_port]

      second_port = described_class.call(station:)[:screens].first[:stream_port]
      hall = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      cover_horizon(station).each { |playlist| add_slot(playlist, hall, asset:) }
      ports = described_class.call(station:)[:screens].map { |item| item[:stream_port] }

      expect(second_port).to eq(first_port)
      expect(ports).to eq([ first_port, first_port ])
      expect(station.stream_channels.count).to eq(1)
    end

    it "does not open or close channels while a horizon day is missing" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon(station)
      add_slot(horizon_playlist(station, HORIZON_DAY), screen, asset:)
      described_class.call(station:)
      station.playlists.current.find_by!(for_date: HORIZON_DAY + 1).update_columns(status: "superseded")
      stranger = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      add_slot(horizon_playlist(station, HORIZON_DAY), stranger, asset: create(:media_asset, :ready, :with_png_file))

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Entrance"][:stream_port]).to eq(8091)
      expect(screens["Hall"]).not_to have_key(:stream_port)
      expect(station.stream_channels.pluck(:stream_port)).to eq([ 8091 ])
    end

    it "drops the channel once a complete horizon no longer uses its digest" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen, asset:)
      described_class.call(station:)
      screen.reload.update!(network_registered: false)

      payload = described_class.call(station:)

      expect(payload[:screens].first.keys).to eq(%i[id name orientation])
      expect(station.stream_channels).to be_empty
    end

    it "does not enqueue playlist generation when the horizon is incomplete" do
      station = wiring_station
      wired_screen(station, ip: "192.168.33.182")

      expect {
        described_class.call(station:)
      }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
    end
  end
end
