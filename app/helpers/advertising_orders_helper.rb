# frozen_string_literal: true

module AdvertisingOrdersHelper
  def advertising_order_day_for(line, date)
    line.advertising_order_line_days.detect { |day| day.date == date }
  end

  def advertising_grid_months(dates)
    Array(dates).group_by { |date| Date.new(date.year, date.month, 1) }
  end

  def advertising_order_price_rubles(line)
    return if line.price_per_day_cents.blank?

    line.price_per_day_cents / 100
  end

  def unoccupied_dates_for(coverage, line)
    coverage.unoccupied_days.select { |day| day.line.id == line.id }.map(&:date)
  end

  def advertising_clip_option_label(asset)
    name = asset.file.attached? ? asset.file.filename.to_s : asset.id.to_s
    "#{name} (#{asset.duration_seconds}s)"
  end

  def order_screen_hours_label(screen)
    Location::OperatingHours.compact_label(screen.effective_operating_hours).presence ||
      t("operating_hours.unset")
  end

  def order_screen_selected?(screen)
    Array(@selected_screen_ids).include?(screen.id)
  end

  def order_clock_hhmm(value)
    return if value.blank?
    return value.strftime("%H:%M") if value.respond_to?(:strftime)

    value.to_s[0, 5]
  end

  def order_screen_meta(screen)
    return if screen.blank?

    [ screen.location&.name, screen.station&.name ].compact.join(" · ")
  end

  def order_form_windows
    @advertising_order.advertising_order_windows.filter_map do |window|
      start_s = order_clock_hhmm(window.starts_at)
      end_s = order_clock_hhmm(window.ends_at)
      next if start_s.blank? || end_s.blank?

      { start: start_s, end: end_s }
    end
  end

  def order_form_time_zone
    @advertising_order.organization&.time_zone || @form_organization&.time_zone || "UTC"
  end

  def order_screen_hours_json(screen)
    windows = order_form_windows
    windows = [ { start: "09:00", end: "12:00" } ] if windows.empty?
    Array(@grid_dates).to_h do |date|
      hours = Advertising::ScreenDayHours.call(
        screen: screen,
        date: date,
        windows: windows,
        time_zone: order_form_time_zone
      ).hours
      [ date.iso8601, hours ]
    end
  end

  def order_line_field_locals(line, index)
    screen = line.screen
    {
      line: line,
      index: index,
      screen_id: screen&.id || "NEW_SCREEN",
      screen_name: screen&.name || t("advertising_orders.form.screen"),
      screen_meta: order_screen_meta(screen),
      hours_json: screen ? order_screen_hours_json(screen) : {}
    }
  end
end
