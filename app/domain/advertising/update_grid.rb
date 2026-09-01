# frozen_string_literal: true

module Advertising
  class UpdateGrid < BaseService
    def initialize(order:, lines:)
      @order = order
      @lines_attrs = Array(lines)
    end

    def call
      staged = stage_lines
      if invalid?(staged)
        order.association(:advertising_order_lines).target = staged
        raise InvalidGrid.new(order)
      end

      persist!
      RecalculateTotals.call(order: order)
      order.reload
    end

    private

    attr_reader :order, :lines_attrs

    def stage_lines
      lines_attrs.map { |attrs| stage_line(attrs.to_h.symbolize_keys) }
    end

    def stage_line(attrs)
      group = BroadcastPointGroup.find(attrs.fetch(:broadcast_point_group_id))
      line = AdvertisingOrderLine.new(
        advertising_order: order,
        broadcast_point_group: group,
        price_per_day_cents: attrs.fetch(:price_per_day_cents)
      )
      Array(attrs[:days]).each do |day_attrs|
        day_attrs = day_attrs.to_h.symbolize_keys
        shows = day_attrs[:shows].to_i
        next if shows <= 0

        day = line.advertising_order_line_days.build(
          date: Date.parse(day_attrs.fetch(:date).to_s),
          shows: shows
        )
        validate_day!(line, day)
      end
      validate_line!(line)
      line
    end

    def validate_line!(line)
      return if line.broadcast_point_group.locations_with_operating_hours?

      line.errors.add(:broadcast_point_group, :missing_operating_hours)
    end

    def validate_day!(line, day)
      hours = OperatingHours.call(
        group: line.broadcast_point_group,
        date: day.date,
        time_zone: time_zone
      )
      if hours.zero?
        day.errors.add(:date, :no_operating_hours)
        return
      end
      return if (day.shows % hours).zero?

      lower = (day.shows / hours) * hours
      day.errors.add(:shows, :not_divisible, hours: hours, lower: lower, upper: lower + hours)
    end

    def invalid?(lines)
      lines.any? { |line| line.errors.any? || line.advertising_order_line_days.any? { |day| day.errors.any? } }
    end

    def persist!
      AdvertisingOrder.transaction do
        incoming_group_ids = lines_attrs.map { |attrs| attrs.to_h.symbolize_keys.fetch(:broadcast_point_group_id).to_i }
        order.advertising_order_lines.where.not(broadcast_point_group_id: incoming_group_ids).find_each(&:destroy!)

        lines_attrs.each do |attrs|
          attrs = attrs.to_h.symbolize_keys
          line = order.advertising_order_lines.find_or_initialize_by(
            broadcast_point_group_id: attrs.fetch(:broadcast_point_group_id)
          )
          line.price_per_day_cents = attrs.fetch(:price_per_day_cents)
          line.save!

          incoming_dates = Array(attrs[:days]).filter_map do |day_attrs|
            day_attrs = day_attrs.to_h.symbolize_keys
            next if day_attrs[:shows].to_i <= 0

            Date.parse(day_attrs.fetch(:date).to_s)
          end
          line.advertising_order_line_days.where.not(date: incoming_dates).find_each(&:destroy!)

          Array(attrs[:days]).each do |day_attrs|
            day_attrs = day_attrs.to_h.symbolize_keys
            shows = day_attrs[:shows].to_i
            next if shows <= 0

            day = line.advertising_order_line_days.find_or_initialize_by(date: Date.parse(day_attrs.fetch(:date).to_s))
            day.shows = shows
            day.save!
          end
        end
      end
    end

    def time_zone
      order.organization.time_zone
    end
  end
end
