# frozen_string_literal: true

module CommercialQuota
  # Allowed commercial seconds for one clock hour = operating minutes ∩ hour × percent / 100.
  # Multi-location groups use the strictest (min) allowance.
  class HourlyAllowance < ServiceObject
    def initialize(group:, hour_start:, percent:, time_zone: "UTC")
      @group = group
      @hour_start = hour_start
      @percent = percent.to_i
      @time_zone = time_zone
    end

    def call
      locations = group.screens.includes(station: :location).map { |s| s.station.location }.uniq
      return 0 if locations.empty? || percent <= 0

      allowances = locations.map { |location| location_allowance_seconds(location) }
      allowances.min || 0
    end

    private

    attr_reader :group, :hour_start, :percent, :time_zone

    def location_allowance_seconds(location)
      local = hour_start.in_time_zone(time_zone)
      minutes = location.operating_minutes_in_hour(local)
      ((minutes * 60) * percent / 100.0).floor
    end
  end
end
