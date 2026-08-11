# frozen_string_literal: true

module ApplicationHelper
  def schedule_datetime_field_value(time, time_zone)
    return "" if time.blank?

    time.in_time_zone(time_zone).strftime("%Y-%m-%dT%H:%M")
  end

  def flash_alert_class(type)
    case type.to_s
    when "notice" then "alert-success"
    when "warning" then "alert-warning"
    else "alert-error"
    end
  end
end
