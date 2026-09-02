# frozen_string_literal: true

module Playlists
  # Transaction-scoped advisory lock for playlist generation (KTD5).
  # Namespace is distinct from Airtime::ScreenLock (874_201).
  class StationDateLock < BaseService
    NAMESPACE = 874_202

    def initialize(station:)
      @station = station
    end

    def call
      ApplicationRecord.connection.execute(
        ApplicationRecord.sanitize_sql_array(
          [ "SELECT pg_advisory_xact_lock(?, ?)", NAMESPACE, station.id ]
        )
      )
      station.id
    end

    private

    attr_reader :station
  end
end
