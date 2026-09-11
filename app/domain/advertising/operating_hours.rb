# frozen_string_literal: true

module Advertising
  # Min number of operating clock-hours among locations of a group on a calendar date.
  class OperatingHours < BaseService
    def initialize(group:, date:, time_zone:)
      @group = group
      @date = date
      @time_zone = time_zone
    end

    def call
      locations = group.screens.includes(station: :location).filter_map { |screen| screen.station&.location }.uniq
      return 0 if locations.empty?

      locations.map { |location| hours_for(location) }.min || 0
    end

    private

    attr_reader :group, :date, :time_zone

    def hours_for(location)
      zone = Time.find_zone!(time_zone)
      (0..23).count do |hour|
        local = zone.local(date.year, date.month, date.day, hour, 0, 0)
        location.operating_minutes_in_hour(local).positive?
      end
    end
  end
end
