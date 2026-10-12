# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent::ConfigBuilder do
  describe '.call' do
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
  end
end
