# frozen_string_literal: true

module Advertising
  class ScreenDayHours < BaseService
    Result = Data.define(:hours, :ranges)

    def initialize(screen:, date:, windows:, time_zone:)
      @screen = screen
      @date = date
      @windows = windows
      @time_zone = time_zone
    end

    def call
      Result.new(hours: counted_hours, ranges: intersecting_ranges)
    end

    def self.open_clock_hours(screen:, date:, time_zone:)
      zone = Time.find_zone!(time_zone)
      hours = screen.effective_operating_hours
      (0..23).select do |hour|
        local = zone.local(date.year, date.month, date.day, hour, 0, 0)
        Location::OperatingHours.minutes_in_hour(hours, local).positive?
      end
    end

    private

    attr_reader :screen, :date, :windows, :time_zone

    def counted_hours
      self.class.open_clock_hours(screen: screen, date: date, time_zone: time_zone).count do |hour|
        local = zone.local(date.year, date.month, date.day, hour, 0, 0)
        Location::OperatingHours.minutes_in_hour(order_hours_hash, local).positive?
      end
    end

    def intersecting_ranges
      screen_windows = Location::OperatingHours.day_windows(screen_hours, date)
      pieces = []

      normalized_windows.each do |order_window|
        screen_windows.each do |screen_window|
          start_s = [ order_window[:start], screen_window[:start] ].max
          end_s = [ order_window[:end], screen_window[:end] ].min
          next if start_s >= end_s

          starts_at = Location::OperatingHours.local_wall_clock(zone, date, start_s)
          ends_at = Location::OperatingHours.local_wall_clock(zone, date, end_s)
          next if starts_at.blank? || ends_at.blank? || ends_at <= starts_at

          pieces << [ starts_at, ends_at ]
        end
      end

      merge_ranges(pieces)
    end

    def merge_ranges(ranges)
      ranges.sort_by(&:first).each_with_object([]) do |(starts_at, ends_at), merged|
        last = merged.last
        if last && last[1] >= starts_at
          last[1] = [ last[1], ends_at ].max
        else
          merged << [ starts_at, ends_at ]
        end
      end
    end

    def screen_hours
      screen.effective_operating_hours
    end

    def order_hours_hash
      { Location::OperatingHours.day_key_for(date) => normalized_windows.map { |window|
        { "start" => window[:start], "end" => window[:end] }
      } }
    end

    def normalized_windows
      Array(windows).filter_map do |window|
        start_s, end_s = clock_pair(window)
        next if start_s.blank? || end_s.blank?

        { start: start_s, end: end_s }
      end
    end

    def clock_pair(window)
      if window.respond_to?(:starts_at)
        [ clock(window.starts_at), clock(window.ends_at) ]
      else
        hash = window.respond_to?(:to_h) ? window.to_h : {}
        [
          clock(hash[:start] || hash["start"] || hash[:starts_at] || hash["starts_at"]),
          clock(hash[:end] || hash["end"] || hash[:ends_at] || hash["ends_at"])
        ]
      end
    end

    def clock(value)
      case value
      when Time, ActiveSupport::TimeWithZone then value.strftime("%H:%M")
      else
        value.to_s[0, 5].presence
      end
    end

    def zone
      @zone ||= Time.find_zone!(time_zone)
    end
  end
end
