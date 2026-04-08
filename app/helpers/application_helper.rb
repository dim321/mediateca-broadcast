module ApplicationHelper
  def schedule_datetime_field_value(time, time_zone)
    return "" if time.blank?

    time.in_time_zone(time_zone).strftime("%Y-%m-%dT%H:%M")
  end
end
