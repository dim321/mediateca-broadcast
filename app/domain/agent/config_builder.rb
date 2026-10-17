# frozen_string_literal: true

module Agent
  class ConfigBuilder < BaseService
    def initialize(station:)
      @station = station
    end

    def call
      station.with_lock do
        timelines = ScreenTimelines.call(station:)
        ports = StreamChannels::Reconcile.call(
          station:,
          digests_by_screen_id: timelines.digests_by_screen_id,
          horizon_complete: timelines.complete
        )
        build_payload(ports)
      end
    end

    private

    attr_reader :station

    def build_payload(ports_by_screen_id)
      payload = {
        station_id: station.id,
        offline_cache_hours: station.offline_cache_hours,
        screens: station.screens.order(:id).map { |screen| screen_payload(screen, ports_by_screen_id) }
      }
      payload[:tv_monitor] = tv_monitor_payload if station.tv_monitor
      payload
    end

    def tv_monitor_payload
      monitor = station.tv_monitor
      {
        health_interval_seconds: monitor.health_interval_seconds,
        auto_restart_when_not_playing: monitor.auto_restart_when_not_playing,
        telemetry_interval_seconds: monitor.telemetry_interval_seconds
      }
    end

    def screen_payload(screen, ports_by_screen_id)
      payload = {
        id: screen.id,
        name: screen.name,
        orientation: screen.orientation
      }
      return payload unless ScreenWiring.wired?(screen)

      payload[:adb_serial] = ScreenWiring.adb_serial(screen)
      mac = ScreenWiring.mac(screen)
      payload[:mac] = mac if mac
      port = ports_by_screen_id[screen.id]
      payload[:stream_port] = port if port
      payload
    end
  end
end
