# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent::ConfigBuilder do
  describe '.call' do
    it 'builds cache policy and the station screen map' do
      station = create(:station, organization: create(:organization, :operator), offline_cache_hours: 12)
      screen = create(:screen, organization: station.organization, station:)

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
  end
end
