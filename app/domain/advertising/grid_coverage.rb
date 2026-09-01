# frozen_string_literal: true

module Advertising
  class GridCoverage < BaseService
    DayCoverage = Data.define(:line, :date, :occupied) do
      def occupied? = occupied
    end

    Result = Data.define(:days) do
      def unoccupied_days = days.reject(&:occupied?)
    end

    def initialize(order:)
      @order = order
    end

    def call
      time_zone = order.organization.time_zone
      days = order.advertising_order_lines.flat_map do |line|
        line.advertising_order_line_days.sort_by(&:date).map do |day|
          DayCoverage.new(
            line: line,
            date: day.date,
            occupied: Coverage.occupied?(line: line, date: day.date, time_zone: time_zone)
          )
        end
      end
      Result.new(days: days)
    end

    private

    attr_reader :order
  end
end
