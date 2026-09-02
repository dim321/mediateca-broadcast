# frozen_string_literal: true

module Playlists
  class GenerateForDateJob < ApplicationJob
    queue_as :default

    def perform(station_id, date_iso)
      station = Station.find_by(id: station_id)
      return if station.nil?

      GenerateForDate.call(station: station, for_date: Date.iso8601(date_iso))
    end
  end
end
