# frozen_string_literal: true

module Playlists
  class DispatchHorizonJob < ApplicationJob
    queue_as :default

    def perform
      Station.find_each do |station|
        GenerateStationHorizonJob.perform_later(station.id)
      end
    end
  end
end
