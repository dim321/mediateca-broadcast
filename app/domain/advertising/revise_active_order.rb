# frozen_string_literal: true

module Advertising
  class ReviseActiveOrder < BaseService
    Result = Data.define(:order, :quota_exceeded)

    def self.call(options)
      new(**options).call
    end

    def initialize(
      order:,
      shows_per_hour:,
      distribution_strategy:,
      windows:,
      screen_ids:,
      lines:,
      media_assets: nil,
      grid_from: nil,
      grid_to: nil,
      product_name: nil,
      placement_kind: nil
    )
      @order = order
      @shows_per_hour = shows_per_hour
      @distribution_strategy = distribution_strategy
      @windows = windows
      @screen_ids = Array(screen_ids)
      @lines = lines
      @media_assets = media_assets
      @grid_from = grid_from
      @grid_to = grid_to
      @product_name = product_name
      @placement_kind = placement_kind
    end

    def call
      validate!

      plans_to_regen = []
      document_changed = false

      MediaPlan.transaction do
        Airtime::ScreenLock.call(screen_ids: lock_ids)

        document_changed |= persist_frequency_and_strategy!
        document_changed |= replace_windows_if_changed!

        document_changed |= recompute_future_line_days!(plans_to_regen)

        Advertising::RecalculateTotals.call(order: order)

        if document_changed
          order.update!(document_version: order.document_version + 1)
        end
      end

      plans_to_regen.uniq.each { |plan| Playlists::EnqueueRegen.from_plan(plan) }

      Result.new(order: order.reload, quota_exceeded: false)
    end

    private

    attr_reader :order, :shows_per_hour, :distribution_strategy, :windows, :screen_ids, :lines,
                :media_assets, :grid_from, :grid_to, :product_name, :placement_kind

    def validate!
      raise Error, I18n.t("advertising.errors.order_not_revisable") unless order.active?

      assert_frozen_fields!
      assert_grid_bounds!
      assert_locked_days!
      assert_future_start_present!
      assert_shows_per_hour!
      assert_windows!
    end

    def persist_frequency_and_strategy!
      changed = false
      if order.shows_per_hour != shows_per_hour
        order.update!(shows_per_hour: shows_per_hour)
        changed = true
      end
      if order.distribution_strategy.to_s != distribution_strategy.to_s
        order.update!(distribution_strategy: distribution_strategy)
        changed = true
      end
      changed
    end

    def replace_windows_if_changed!
      new_pairs = window_pairs(windows)
      old_pairs = order.advertising_order_windows.map { |window| clock_pair(window.starts_at, window.ends_at) }.sort
      return false if new_pairs == old_pairs

      order.advertising_order_windows.destroy_all
      Array(windows).each do |window|
        hash = window.respond_to?(:to_h) ? window.to_h : {}
        starts_at = hash[:starts_at] || hash["starts_at"]
        ends_at = hash[:ends_at] || hash["ends_at"]
        order.advertising_order_windows.create!(starts_at: starts_at, ends_at: ends_at)
      end
      true
    end

    def recompute_future_line_days!(plans_to_regen)
      changed = false
      normalized_screen_ids = screen_ids.map(&:to_i)

      order.advertising_order_lines.includes(:advertising_order_line_days, :screen).find_each do |line|
        screen_index = normalized_screen_ids.index(line.screen_id)
        next if screen_index.nil?

        desired = desired_future_days_for(line, screen_index)

        line.advertising_order_line_days.select { |day| day.date > today }.each do |day|
          unless desired.key?(day.date)
            remove_future_line_day!(day, plans_to_regen)
            changed = true
            next
          end

          computed_shows = desired.fetch(day.date)
          if day.shows != computed_shows
            day.update!(shows: computed_shows)
            changed = true
          end

          day_result = screen_day_hours(line, day.date)
          update_matching_plans!(line, day.date, day_result.ranges, plans_to_regen)
        end

        desired.each do |date, computed_shows|
          next if line.advertising_order_line_days.any? { |stored| stored.date == date }

          add_future_line_day!(line, date, computed_shows, plans_to_regen)
          changed = true
        end
      end

      changed
    end

    def desired_future_days_for(line, screen_index)
      submitted = line_for_screen(line.screen_id)
      return {} unless submitted

      {}.tap do |result|
        Array(submitted[:days]).each do |entry|
          date = parse_date(entry[:date])
          next unless date > today
          next unless date >= period_start && date <= effective_grid_ceiling
          next if skipped?(entry)

          day_result = screen_day_hours(line, date)
          computed_shows = Advertising::DayShows.call(
            date: date,
            shows_per_hour: shows_per_hour,
            hours: day_result.hours,
            distribution_strategy: order.distribution_strategy,
            screen_index: screen_index,
            screen_count: screen_ids.size
          )
          next unless computed_shows.positive?

          result[date] = computed_shows
        end
      end
    end

    def remove_future_line_day!(day, plans_to_regen)
      line = day.advertising_order_line
      overlapping_plans(line, day.date).each do |plan|
        Airtime::Cancel.call(plan: plan, enqueue_regen: false)
        plans_to_regen << plan
      end
      day.destroy!
    end

    def add_future_line_day!(line, date, computed_shows, plans_to_regen)
      line.advertising_order_line_days.create!(date: date, shows: computed_shows)

      screen_day_hours(line, date).ranges.each do |starts_at, ends_at|
        plan = Airtime::OccupyWithPlan.call(
          organization: order.organization,
          rotation: order.rotation,
          starts_at: starts_at,
          ends_at: ends_at,
          placement_kind: order.placement_kind,
          shows_per_hour: shows_per_hour,
          screens: [ line.screen ],
          order_claim: true,
          advertising_order_line: line,
          enqueue_regen: false
        )
        plans_to_regen << plan
      end
    end

    def screen_day_hours(line, date)
      Advertising::ScreenDayHours.call(
        screen: line.screen,
        date: date,
        windows: order.advertising_order_windows,
        time_zone: time_zone
      )
    end

    def effective_grid_ceiling
      @effective_grid_ceiling ||= begin
        ceiling = period_end
        ceiling = [ parse_date(grid_to), ceiling ].min if grid_to.present?
        ceiling
      end
    end

    def update_matching_plans!(line, date, ranges, plans_to_regen)
      if plan_bounds_match?(line, date, ranges)
        overlapping_plans(line, date).each do |plan|
          next if plan.shows_per_hour == shows_per_hour

          plan.update_columns(shows_per_hour: shows_per_hour, updated_at: Time.current)
          plans_to_regen << plan
        end
        return
      end

      overlapping_plans(line, date).each do |plan|
        Airtime::Cancel.call(plan: plan, enqueue_regen: false)
        plans_to_regen << plan
      end

      ranges.each do |starts_at, ends_at|
        plan = Airtime::OccupyWithPlan.call(
          organization: order.organization,
          rotation: order.rotation,
          starts_at: starts_at,
          ends_at: ends_at,
          placement_kind: order.placement_kind,
          shows_per_hour: shows_per_hour,
          screens: [ line.screen ],
          order_claim: true,
          advertising_order_line: line,
          enqueue_regen: false
        )
        plans_to_regen << plan
      end
    end

    def plan_bounds_match?(line, date, ranges)
      overlapping_plans(line, date).map { |plan| [ plan.starts_at, plan.ends_at ] }.sort == ranges.sort
    end

    def overlapping_plans(line, date)
      from, to = local_day_bounds(date)
      line.media_plans.active.where("starts_at < ? AND ends_at > ?", to, from)
    end

    def local_day_bounds(date)
      zone = Time.find_zone!(time_zone)
      from = zone.local(date.year, date.month, date.day)
      to = zone.local((date + 1).year, (date + 1).month, (date + 1).day)
      [ from, to ]
    end

    def lock_ids
      (screen_ids.map(&:to_i) + order.advertising_order_lines.pluck(:screen_id)).uniq
    end

    def window_pairs(source_windows)
      Array(source_windows).filter_map do |window|
        hash = window.respond_to?(:to_h) ? window.to_h : {}
        start_clock = hash[:starts_at] || hash["starts_at"]
        end_clock = hash[:ends_at] || hash["ends_at"]
        next if start_clock.blank? || end_clock.blank?

        [ clock(start_clock), clock(end_clock) ]
      end.sort
    end

    def clock_pair(starts_at, ends_at)
      [ clock(starts_at), clock(ends_at) ]
    end

    def clock(value)
      case value
      when Time, ActiveSupport::TimeWithZone then value.strftime("%H:%M")
      else
        value.to_s[0, 5].presence
      end
    end

    def time_zone
      order.organization.time_zone
    end

    def assert_frozen_fields!
      if product_name.present? && product_name != order.product_name
        raise Error, I18n.t("advertising.errors.frozen_field_changed")
      end
      if placement_kind.present? && placement_kind.to_s != order.placement_kind.to_s
        raise Error, I18n.t("advertising.errors.frozen_field_changed")
      end
    end

    def assert_grid_bounds!
      if grid_from.present? && parse_date(grid_from) != period_start
        raise Error, I18n.t("advertising.errors.start_date_changed")
      end

      if grid_to.present? && parse_date(grid_to) > period_end
        raise Error, I18n.t("advertising.errors.end_date_extended")
      end

      normalized_lines.each do |line|
        Array(line[:days]).each do |day|
          next unless parse_date(day[:date]) > period_end

          raise Error, I18n.t("advertising.errors.end_date_extended")
        end
      end
    end

    def assert_locked_days!
      order.advertising_order_line_days.includes(:advertising_order_line).each do |stored_day|
        next if stored_day.date > today

        screen_id = stored_day.advertising_order_line.screen_id
        entry = day_entry(line_for_screen(screen_id), stored_day.date)

        if entry.nil? || skipped?(entry) || entry[:shows].to_i != stored_day.shows
          raise Error, I18n.t("advertising.errors.locked_day_changed")
        end
      end
    end

    def assert_future_start_present!
      return unless period_start > today

      present = screen_ids.any? do |screen_id|
        entry = day_entry(line_for_screen(screen_id), period_start)
        entry && !skipped?(entry)
      end

      raise Error, I18n.t("advertising.errors.future_start_removed") unless present
    end

    def assert_shows_per_hour!
      previous = order.shows_per_hour
      order.shows_per_hour = shows_per_hour
      begin
        AssertShowsPerHour.call(order: order, screens: Screen.where(id: screen_ids))
      rescue StandardError
        order.shows_per_hour = previous
        raise
      end
      order.shows_per_hour = previous
    end

    def assert_windows!
      if Array(windows).empty?
        record = AdvertisingOrderWindow.new(advertising_order: order)
        return if record.valid?

        raise Error, record.errors.full_messages.to_sentence
      end

      Array(windows).each do |window|
        hash = window.respond_to?(:to_h) ? window.to_h : {}
        starts_at = hash[:starts_at] || hash["starts_at"]
        ends_at = hash[:ends_at] || hash["ends_at"]
        record = AdvertisingOrderWindow.new(
          advertising_order: order,
          starts_at: starts_at,
          ends_at: ends_at
        )
        next if record.valid?

        raise Error, record.errors.full_messages.to_sentence
      end
    end

    def period_start
      @period_start ||= order.advertising_order_line_days.minimum(:date)
    end

    def period_end
      @period_end ||= order.advertising_order_line_days.maximum(:date)
    end

    def today
      @today ||= Time.find_zone!(time_zone).today
    end

    def normalized_lines
      @normalized_lines ||= Array(lines).map { |line| line.to_h.deep_symbolize_keys }
    end

    def line_for_screen(screen_id)
      normalized_lines.find { |line| line[:screen_id].to_i == screen_id.to_i }
    end

    def day_entry(line, date)
      return nil unless line

      Array(line[:days]).find { |day| parse_date(day[:date]) == date }
    end

    def skipped?(entry)
      value = entry[:skipped]
      value == true || value == 1 || value == "1"
    end

    def parse_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    end
  end
end
