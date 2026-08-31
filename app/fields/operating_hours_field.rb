# frozen_string_literal: true

require "administrate/field/base"

class OperatingHoursField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => Location::OperatingHours::DAY_KEYS.index_with { %i[start end] } }
  end

  def to_s
    return "—" unless configured?

    Location::OperatingHours::DAY_KEYS.filter_map do |day|
      windows = Array(data&.dig(day))
      next if windows.blank?

      parts = windows.map { |w| "#{w['start']}–#{w['end']}" }.join(", ")
      "#{I18n.t("admin.fields.operating_hours.days.#{day}")}: #{parts}"
    end.join("; ")
  end

  def configured?
    Location::OperatingHours::DAY_KEYS.any? { |day| Array(data&.dig(day)).any? }
  end

  def window_for(day)
    Array(data&.dig(day)).first || {}
  end
end
