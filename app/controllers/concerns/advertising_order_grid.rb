# frozen_string_literal: true

module AdvertisingOrderGrid
  extend ActiveSupport::Concern

  private

  def persist_grid!(order)
    @grid_dates ||= grid_dates
    persist_windows!(order)
    payload = computed_lines_payload(order)
    return if payload.empty?

    screens = form_screen_ids.filter_map { |id| Screen.find_by(id: id) }
    Advertising::AssertShowsPerHour.call(order: order, screens: screens)

    order.advertising_order_lines.reset
    Advertising::UpdateGrid.call(order: order, lines: payload)
  end

  def persist_windows!(order)
    order.advertising_order_windows.destroy_all
    Array(order_params[:windows]).each do |window|
      starts_at = window[:starts_at].presence
      ends_at = window[:ends_at].presence
      next if starts_at.blank? || ends_at.blank?

      order.advertising_order_windows.create!(starts_at: starts_at, ends_at: ends_at)
    end
  end

  def computed_lines_payload(order)
    skipped = skipped_dates_by_screen
    screen_ids = form_screen_ids
    screen_ids.filter_map.with_index do |screen_id, screen_index|
      screen = Screen.find_by(id: screen_id)
      next unless screen

      days = dates_for_screen(screen_id).map do |date|
        if skipped.dig(screen_id, date)
          { date: date, shows: 0 }
        else
          hours = Advertising::ScreenDayHours.call(
            screen: screen,
            date: date,
            windows: order.advertising_order_windows,
            time_zone: order.organization.time_zone
          ).hours
          { date: date, shows: distributed_shows(order, date, screen_index, screen_ids.size,
            order.shows_per_hour.to_i * hours) }
        end
      end
      { screen_id: screen_id, days: days }
    end
  end

  def distributed_shows(order, date, screen_index, screen_count, shows)
    case order.distribution_strategy
    when "weekdays"
      weekend?(date) ? 0 : shows
    when "weekends"
      weekend?(date) ? shows : 0
    when "even_days"
      date.day.even? ? shows : 0
    when "odd_days"
      date.day.odd? ? shows : 0
    when "chess"
      first_half_day = chess_day_offset(date).even?
      in_first_half = screen_index < (screen_count / 2.0).ceil
      first_half_day == in_first_half ? shows : 0
    else
      shows
    end
  end

  def weekend?(date)
    date.saturday? || date.sunday?
  end

  def chess_day_offset(date)
    (date - Array(@grid_dates).first).to_i
  end

  def form_screen_ids
    ids = Array(order_params[:screen_ids]).map(&:to_i).reject(&:zero?)
    return ids if ids.any?

    ids = line_rows.filter_map { |row| row[:screen_id].to_i if row[:screen_id].present? }.reject(&:zero?)
    return ids if ids.any?

    Array(@advertising_order&.advertising_order_lines).map(&:screen_id).compact
  end

  def dates_for_screen(screen_id)
    row = line_rows.find { |candidate| candidate[:screen_id].to_i == screen_id }
    dates = Array(row&.fetch(:days, nil)).filter_map do |day|
      Date.iso8601(day[:date].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    dates.presence || Array(@grid_dates)
  end

  def skipped_dates_by_screen
    skipped = {}
    line_rows.each do |row|
      screen_id = row[:screen_id].to_i
      next if screen_id.zero?

      Array(row[:days]).each do |day|
        date = Date.iso8601(day[:date].to_s)
        next unless day[:skipped].to_s == "1" || day[:shows].to_s == "0"

        skipped[screen_id] ||= {}
        skipped[screen_id][date] = true
      rescue ArgumentError, TypeError
        next
      end
    end
    skipped
  end

  def line_rows
    raw = order_params[:lines]
    list = raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash) ? raw.values : Array(raw)
    list.map { |row| row.to_h.deep_symbolize_keys }
  end

  def selected_screen_ids
    raw = order_params[:screen_ids]
    ids = Array(raw).map(&:to_i).reject(&:zero?)
    return ids if ids.any?

    Array(@advertising_order&.advertising_order_lines).map(&:screen_id).compact
  end

  def load_order_screens
    @order_screens = Fleet::ScreensForOrderPicker.call
    @selected_screen_ids = selected_screen_ids
  end

  def load_occupancy
    group = occupancy_group
    @occupied_slots = if group
      Airtime::OccupancyPresenter.call(broadcast_point_group: group)
    else
      []
    end
  end

  def occupancy_group
    screen = occupancy_screen
    return if screen.blank?

    org = occupancy_organization
    screen.broadcast_point_groups.find_by(organization: org) || screen.broadcast_point_groups.first
  end

  def occupancy_screen
    id = Array(order_params[:screen_ids]).map(&:to_i).find(&:positive?)
    id ||= @advertising_order&.advertising_order_lines&.first&.screen_id
    Screen.find_by(id: id) if id
  end

  def occupancy_organization
    @form_organization || Current.user&.organization
  end

  def grid_dates
    from = parse_grid_date(params[:grid_from]) || order_grid_bounds&.begin || Date.current.tomorrow
    to = parse_grid_date(params[:grid_to]) || order_grid_bounds&.end || Date.current.end_of_month
    from, to = to, from if from > to
    (from..to).to_a
  end

  def order_grid_bounds
    dates = @advertising_order&.advertising_order_lines&.flat_map do |line|
      line.advertising_order_line_days.map(&:date)
    end&.compact
    return if dates.blank?

    dates.min..dates.max
  end

  def parse_grid_date(value)
    str = value.to_s.strip
    return if str.blank?

    if str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(str)
    elsif str.match?(/\A\d{1,2}\.\d{1,2}\.\d{4}\z/)
      Date.strptime(str, "%d.%m.%Y")
    end
  rescue ArgumentError, TypeError
    nil
  end

  def order_header_shows_per_hour
    order_params[:shows_per_hour].presence&.to_i
  end
end
