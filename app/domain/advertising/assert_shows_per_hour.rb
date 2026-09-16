# frozen_string_literal: true

module Advertising
  class AssertShowsPerHour < BaseService
    def initialize(order:, screens:)
      @order = order
      @screens = Array(screens)
    end

    def call
      return if screens.empty?

      allowed = Portraits::FrequencySet.intersection_for_screens(screens)
      if allowed.empty?
        order.errors.add(:advertising_order_lines, :empty_frequency_intersection)
        raise InvalidGrid.new(order)
      end
      return if order.shows_per_hour.nil?
      return if allowed.include?(order.shows_per_hour)

      order.errors.add(:shows_per_hour, :not_in_portrait_intersection)
      raise InvalidGrid.new(order)
    end

    private

    attr_reader :order, :screens
  end
end
