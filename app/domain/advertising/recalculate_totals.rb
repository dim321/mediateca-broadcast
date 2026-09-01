# frozen_string_literal: true

module Advertising
  class RecalculateTotals < BaseService
    def initialize(order:)
      @order = order
    end

    def call
      order.advertising_order_lines.find_each do |line|
        days = line.advertising_order_line_days
        line.update!(
          total_shows: days.sum(:shows),
          total_sum_cents: days.count * line.price_per_day_cents
        )
      end

      lines = order.advertising_order_lines
      order.update!(
        total_shows: lines.sum(:total_shows),
        total_sum_cents: [ lines.sum(:total_sum_cents) - order.discount_cents, 0 ].max
      )
      order
    end

    private

    attr_reader :order
  end
end
