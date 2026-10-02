# frozen_string_literal: true

module Advertising
  class DayShows < BaseService
    def initialize(date:, shows_per_hour:, hours:, distribution_strategy:, screen_index:, screen_count:)
      @date = date
      @shows_per_hour = shows_per_hour.to_i
      @hours = hours.to_i
      @distribution_strategy = distribution_strategy.to_s
      @screen_index = screen_index
      @screen_count = screen_count
    end

    def call
      base = shows_per_hour * hours
      case distribution_strategy
      when "weekdays"
        weekend? ? 0 : base
      when "weekends"
        weekend? ? base : 0
      when "even_days"
        date.day.even? ? base : 0
      when "odd_days"
        date.day.odd? ? base : 0
      when "chess"
        first_half_day = date.day.odd?
        in_first_half = screen_index < (screen_count / 2.0).ceil
        first_half_day == in_first_half ? base : 0
      else
        base
      end
    end

    private

    attr_reader :date, :shows_per_hour, :hours, :distribution_strategy, :screen_index, :screen_count

    def weekend?
      date.saturday? || date.sunday?
    end
  end
end
