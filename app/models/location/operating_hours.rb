# frozen_string_literal: true

# Weekly operating hours stored on Location as JSONB.
# Shape: { "mon" => [{ "start" => "09:00", "end" => "18:00" }], ... }
# Days: mon..sun. Empty hash / no windows => hours not configured.
module Location::OperatingHours
  DAY_KEYS = %w[mon tue wed thu fri sat sun].freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  def self.normalize(hours)
    return {} if hours.blank?

    hash = if hours.respond_to?(:to_unsafe_h)
      hours.to_unsafe_h
    elsif hours.respond_to?(:to_h)
      hours.to_h
    else
      {}
    end

    DAY_KEYS.index_with do |day|
      Array(hash[day] || hash[day.to_sym]).filter_map do |window|
        next unless window.respond_to?(:[])

        start_s = normalize_clock(window["start"] || window[:start])
        end_s = normalize_clock(window["end"] || window[:end])
        next if start_s.blank? || end_s.blank?

        { "start" => start_s, "end" => end_s }
      end
    end.reject { |_day, windows| windows.blank? }
  end

  def self.normalize_clock(value)
    raw = value.to_s.strip
    return if raw.blank?

    raw[0, 5]
  end
  private_class_method :normalize_clock

  def operating_hours_configured?
    DAY_KEYS.any? { |day| windows_for(day).any? }
  end

  # Minutes of this location open during the clock hour that contains +local_time+.
  # +local_time+ must already be in the wall-clock zone used for the weekly schedule.
  def operating_minutes_in_hour(local_time)
    return 0 unless operating_hours_configured?

    hour_start = local_time.change(min: 0, sec: 0)
    hour_end = hour_start + 1.hour
    day = DAY_KEYS[local_time.wday.zero? ? 6 : local_time.wday - 1]

    windows_for(day).sum do |window|
      overlap_minutes(window, hour_start, hour_end)
    end
  end

  private

  def windows_for(day)
    raw = operating_hours.is_a?(Hash) ? operating_hours[day] || operating_hours[day.to_sym] : nil
    Array(raw).filter_map { |entry| normalize_window(entry) }
  end

  def normalize_window(entry)
    return unless entry.is_a?(Hash)

    start_s = entry["start"] || entry[:start]
    end_s = entry["end"] || entry[:end]
    return unless start_s.to_s.match?(TIME_FORMAT) && end_s.to_s.match?(TIME_FORMAT)

    { start: start_s.to_s, end: end_s.to_s }
  end

  def overlap_minutes(window, hour_start, hour_end)
    win_start = parse_on_day(hour_start, window[:start])
    win_end = parse_on_day(hour_start, window[:end])
    return 0 if win_end <= win_start

    from = [ win_start, hour_start ].max
    to = [ win_end, hour_end ].min
    return 0 if to <= from

    ((to - from) / 60).to_i
  end

  def parse_on_day(day_time, hhmm)
    h, m = hhmm.split(":").map(&:to_i)
    day_time.change(hour: h, min: m, sec: 0)
  end
end
