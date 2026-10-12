# frozen_string_literal: true

module Agent
  class ConfigBuilder < BaseService
    def initialize(station:)
      @station = station
    end

    def call
      payload = {
        station_id: station.id,
        offline_cache_hours: station.offline_cache_hours,
        screens: station.screens.order(:id).map { |screen| screen_payload(screen) }
      }
      payload[:tv_monitor] = tv_monitor_payload if station.tv_monitor
      payload
    end

    private

    attr_reader :station

    def tv_monitor_payload
      monitor = station.tv_monitor
      {
        health_interval_seconds: monitor.health_interval_seconds,
        auto_restart_when_not_playing: monitor.auto_restart_when_not_playing,
        telemetry_interval_seconds: monitor.telemetry_interval_seconds
      }
    end

    def screen_payload(screen)
      {
        id: screen.id,
        name: screen.name,
        orientation: screen.orientation
      }
    end
  end
end
