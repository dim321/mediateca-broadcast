# frozen_string_literal: true

module Playlists
  class GenerateStationHorizonJob < ApplicationJob
    queue_as :default

    if respond_to?(:limits_concurrency)
      limits_concurrency to: 1, key: ->(station_id) { station_id }, duration: 10.minutes, on_conflict: :discard
    end

    def perform(station_id)
      station = Station.find_by(id: station_id)
      return if station.nil?

      EnqueueRegen.horizon_dates(station).each do |date|
        GenerateForDate.call(station: station, for_date: date)
      end
    end
  end
end
