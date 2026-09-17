# frozen_string_literal: true

module AdvertisingOrdersHelper
  OrderClipRow = Struct.new(:title, :duration_seconds, :media_asset, keyword_init: true)

  def advertising_order_day_for(line, date)
    line.advertising_order_line_days.detect { |day| day.date == date }
  end

  def advertising_grid_months(dates)
    Array(dates).group_by { |date| Date.new(date.year, date.month, 1) }.sort.to_h
  end

  def advertising_grid_month_label(month)
    month_name = I18n.t("date.month_names_nominative")[month.month]
    "#{month_name.capitalize} #{month.year}"
  end

  def order_grid_date_value(date)
    date&.strftime("%d.%m.%Y")
  end

  def order_grid_date_field_tag(name, date, html_class:)
    content_tag(:div, class: "relative", data: { controller: "order-grid-date" }) do
      safe_join([
        text_field_tag(
          name,
          order_grid_date_value(date),
          class: "#{html_class} pr-10",
          placeholder: t("advertising_orders.form.date_placeholder"),
          autocomplete: "off",
          data: {
            order_grid_date_target: "display",
            action: "change->order-grid-date#syncFromDisplay"
          }
        ),
        content_tag(:span, class: "pointer-events-none absolute inset-y-0 right-0 flex w-9 items-center justify-center") do
          order_grid_calendar_icon
        end,
        tag.input(
          type: "date",
          value: date&.iso8601,
          class: "absolute inset-y-0 right-0 w-9 cursor-pointer opacity-0",
          tabindex: -1,
          aria: { label: t("advertising_orders.form.pick_date") },
          data: {
            order_grid_date_target: "picker",
            action: "change->order-grid-date#syncFromPicker"
          }
        )
      ])
    end
  end

  def advertising_order_price_rubles(line)
    return if line.price_per_day_cents.blank?

    line.price_per_day_cents / 100
  end

  def unoccupied_dates_for(coverage, line)
    coverage.unoccupied_days.select { |day| day.line.id == line.id }.map(&:date)
  end

  def advertising_clip_option_label(asset)
    name = advertising_clip_title(asset)
    "#{name} (#{asset.duration_seconds}s)"
  end

  def order_clip_rows(order)
    items = order.rotation&.ordered_items
    if items.present?
      items.filter_map do |item|
        asset = item.media_asset
        next if asset.blank?

        OrderClipRow.new(
          title: advertising_clip_title(asset),
          duration_seconds: item.display_duration_seconds || asset.duration_seconds,
          media_asset: asset
        )
      end
    elsif order.clip_title.present?
      [ OrderClipRow.new(title: order.clip_title, duration_seconds: order.duration_seconds, media_asset: order.media_asset) ]
    else
      []
    end
  end

  def order_clip_row_label(row)
    duration = row.duration_seconds
    return row.title if duration.blank?

    "#{row.title} (#{duration}s)"
  end

  def advertising_clip_title(asset)
    return asset.id.to_s if asset.blank?

    asset.file.attached? ? asset.file.filename.to_s : asset.id.to_s
  end

  def advertising_order_media_asset_option(asset)
    [
      asset.file.attached? ? asset.file.filename.to_s : asset.id.to_s,
      asset.id,
      {
        "data-duration" => asset.duration_seconds,
        "data-content-type" => t("media_assets.index.content_types.#{asset.content_type}"),
        "data-content-kind" => t("media_assets.index.content_kinds.#{asset.content_kind}")
      }
    ]
  end

  def order_form_selected_media_assets(advertising_order)
    advertising_order.rotation&.ordered_items&.filter_map(&:media_asset) || []
  end

  def order_form_available_media_assets(advertising_order, media_assets)
    selected_ids = order_form_selected_media_assets(advertising_order).map(&:id)
    Array(media_assets).reject { |asset| selected_ids.include?(asset.id) }
  end

  def order_screen_hours_label(screen)
    Location::OperatingHours.compact_label(screen.effective_operating_hours).presence ||
      t("operating_hours.unset")
  end

  def order_screen_frequencies_label(screen)
    Array(screen&.broadcast_portrait&.block_frequencies_per_hour).join(", ").presence
  end

  def order_screen_selected?(screen)
    Array(@selected_screen_ids).include?(screen.id)
  end

  def order_shows_per_hour_select_options(advertising_order)
    screens = advertising_order.advertising_order_lines.filter_map(&:screen)
    screens = Array(@order_screens).select { |screen| order_screen_selected?(screen) } if screens.empty?
    Portraits::FrequencySet.intersection_for_screens(screens)
  end

  def order_clock_hhmm(value)
    return if value.blank?
    return value.strftime("%H:%M") if value.respond_to?(:strftime)

    value.to_s[0, 5]
  end

  def order_screen_meta(screen)
    screen&.location&.name
  end

  def order_form_time_zone
    @advertising_order.organization&.time_zone || @form_organization&.time_zone || "UTC"
  end

  def order_screen_hours_json(screen)
    Array(@grid_dates).to_h do |date|
      hours = Advertising::ScreenDayHours.open_clock_hours(
        screen: screen,
        date: date,
        time_zone: order_form_time_zone
      )
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
      hours_json: screen ? order_screen_hours_json(screen) : {},
      shows_total: line.total_shows
    }
  end

  def advertising_order_date_ranges(order)
    dates = order.advertising_order_line_days.map(&:date).compact.uniq.sort
    return t("admin.crud.none") if dates.empty?

    dates.slice_when { |previous, current| current != previous + 1 }.map do |range|
      first_date = range.first
      last_date = range.last
      first_label = first_date.strftime("%d.%m.%Y")
      last_label = last_date.strftime("%d.%m.%Y")

      first_date == last_date ? first_label : "#{first_label}–#{last_label}"
    end.join(", ")
  end

  def advertising_order_day_count(order)
    dates = order.advertising_order_line_days.map(&:date).compact.uniq
    dates.empty? ? t("admin.crud.none") : dates.count
  end

  def advertising_order_windows_label(order)
    windows = order.advertising_order_windows
    return t("admin.crud.none") if windows.empty?

    windows.map do |window|
      "#{window.starts_at.strftime("%H:%M")}–#{window.ends_at.strftime("%H:%M")}"
    end.join(", ")
  end

  def advertising_order_daily_shows_label(order)
    daily_shows = order.advertising_order_line_days.group_by(&:date).values.map do |days|
      days.sum(&:shows)
    end.uniq

    daily_shows.presence&.join(", ") || t("admin.crud.none")
  end

  private

  def order_grid_calendar_icon
    tag.svg(
      xmlns: "http://www.w3.org/2000/svg",
      fill: "none",
      viewBox: "0 0 24 24",
      stroke: "currentColor",
      class: "h-4 w-4 opacity-60",
      "aria-hidden": true
    ) do
      tag.path(
        "stroke-linecap": "round",
        "stroke-linejoin": "round",
        "stroke-width": "1.5",
        d: "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5A2.25 2.25 0 0 1 5.25 5.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"
      )
    end
  end
end
