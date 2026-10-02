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
      Result.new(order: order, quota_exceeded: false)
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
    end

    def period_start
      @period_start ||= order.advertising_order_line_days.minimum(:date)
    end

    def period_end
      @period_end ||= order.advertising_order_line_days.maximum(:date)
    end

    def today
      @today ||= Time.find_zone!(order.organization.time_zone).today
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
