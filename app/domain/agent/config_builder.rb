# frozen_string_literal: true

module Agent
  class ConfigBuilder < BaseService
    def initialize(station:)
      @station = station
    end

    def call
      {
        station_id: station.id,
        offline_cache_hours: station.offline_cache_hours,
        screens: station.screens.order(:id).map { |screen| screen_payload(screen) }
      }
    end

    private

    attr_reader :station

    def screen_payload(screen)
      {
        id: screen.id,
        name: screen.name,
        orientation: screen.orientation
      }
    end
  end
end
