# frozen_string_literal: true

module Advertising
  class PrintSheetComponent < ViewComponent::Base
    include ApplicationHelper

    def initialize(order:)
      @order = order
    end

    attr_reader :order

    def lines
      order.advertising_order_lines.sort_by { |line| line.broadcast_point_group.name }
    end

    def month_blocks
      @month_blocks ||= PrintMonthBlocks.new(placement_dates: placement_dates).call
    end

    def placement_dates
      order.advertising_order_line_days.map(&:date)
    end

    def shows_for(line, date)
      line.advertising_order_line_days.find { |day| day.date == date }&.shows
    end

    def gross_sum_cents
      order.advertising_order_lines.sum(&:total_sum_cents)
    end

    def coefficient_label
      percent = order.coefficient_percent.to_i
      sign = percent.positive? ? "+" : ""
      "#{sign}#{percent}%"
    end

    def duration_label
      return dash if order.duration_seconds.blank?

      I18n.t("advertising.print_sheet.duration_seconds", count: order.duration_seconds)
    end

    def dash
      I18n.t("advertising.print_sheet.dash")
    end

    def cell_value(line, date)
      shows = shows_for(line, date)
      shows.present? ? shows : dash
    end
  end
end
