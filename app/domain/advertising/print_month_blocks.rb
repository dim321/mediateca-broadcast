# frozen_string_literal: true

module Advertising
  PrintMonthBlock = Data.define(:label, :dates)

  class PrintMonthBlocks
    MAX_SINGLE_BLOCK_DAYS = 31

    def initialize(placement_dates:)
      @placement_dates = Array(placement_dates).uniq.sort
    end

    def call
      return [] if placement_dates.empty?

      min_date, max_date = placement_dates.minmax
      span = (max_date - min_date).to_i + 1

      if span <= MAX_SINGLE_BLOCK_DAYS
        [ build_block(min_date..max_date) ]
      else
        month_starts(min_date, max_date).map { |month| build_month_block(month, max_date) }
      end
    end

    private

    attr_reader :placement_dates

    def month_starts(from, to)
      months = []
      cursor = Date.new(from.year, from.month, 1)
      last = Date.new(to.year, to.month, 1)
      while cursor <= last
        months << cursor
        cursor = cursor.next_month
      end
      months
    end

    def build_month_block(month_start, max_date)
      first_in_month = placement_dates.find { |date| date.year == month_start.year && date.month == month_start.month }
      block_start = first_in_month
      block_end = if month_start == Date.new(max_date.year, max_date.month, 1)
        max_date
      else
        month_start.end_of_month
      end
      build_block(block_start..block_end)
    end

    def build_block(range)
      PrintMonthBlock.new(label: block_label(range), dates: range.to_a)
    end

    def block_label(range)
      first = range.first
      last = range.last
      if first.year == last.year && first.month == last.month
        I18n.l(first, format: "%B %Y")
      else
        "#{I18n.l(first, format: '%B %Y')} – #{I18n.l(last, format: '%B %Y')}"
      end
    end
  end
end
