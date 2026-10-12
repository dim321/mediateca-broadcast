# frozen_string_literal: true

module Agent
  class RecordTelemetry < BaseService
    def initialize(station:, payload:)
      @station = station
      @payload = payload.deep_stringify_keys
    end

    def call
      reported_at = Time.iso8601(payload.fetch("reported_at").to_s)
      existing = station.telemetry_snapshot
      return :stale if existing && existing.reported_at > reported_at

      station_row = payload.fetch("station")
      screen_rows = payload.fetch("screens")
      raise ArgumentError, "screens must be an array" unless screen_rows.is_a?(Array)

      Station.transaction do
        write_station(reported_at, station_row, ignored_ids_for(screen_rows))
        write_screens(reported_at, screen_rows)
      end
      :recorded
    end

    private

    attr_reader :station, :payload

    def write_station(reported_at, row, ignored_ids)
      snapshot = station.telemetry_snapshot || station.build_telemetry_snapshot
      snapshot.update!(
        reported_at: reported_at,
        uptime_seconds: integer!(row.fetch("uptime_seconds")),
        package_etag: row.fetch("package_etag", "").to_s,
        broadcast_ok: boolean!(row.fetch("broadcast_ok")),
        ignored_screen_ids: ignored_ids
      )
    end

    def write_screens(reported_at, rows)
      kept_ids = []
      rows.each do |row|
        screen = station.screens.find_by(id: row.fetch("screen_id"))
        next unless screen

        kept_ids << screen.id
        snapshot = ScreenTelemetrySnapshot.find_or_initialize_by(screen:)
        snapshot.update!(
          station: station,
          reported_at: reported_at,
          reachable: boolean!(row.fetch("reachable")),
          agent_ok: boolean!(row.fetch("agent_ok")),
          playing: boolean!(row.fetch("playing")),
          url: row.fetch("url", "").to_s,
          wakefulness: row.fetch("wakefulness", "").to_s,
          stream_port: integer!(row.fetch("stream_port", 0)),
          broadcast_clients: integer!(row.fetch("broadcast_clients", 0)),
          last_error: nullable_string(row["last_error"])
        )
      end
      station.screen_telemetry_snapshots.where.not(screen_id: kept_ids).delete_all
    end

    def ignored_ids_for(rows)
      known = station.screens.where(id: rows.map { |row| row["screen_id"] }).ids
      rows.filter_map { |row| Integer(row.fetch("screen_id")) unless known.include?(Integer(row.fetch("screen_id"))) }
    end

    def boolean!(value)
      return value if value == true || value == false

      raise ArgumentError, "expected boolean"
    end

    def integer!(value)
      Integer(value)
    end

    def nullable_string(value)
      return if value.nil?

      value.to_s
    end
  end
end
