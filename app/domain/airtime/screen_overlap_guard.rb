# frozen_string_literal: true

module Airtime
  # Confirmed bookings must not overlap on shared screens (R6).
  class ScreenOverlapGuard < BaseService
    def initialize(starts_at:, ends_at:, screen_ids:, exclude_booking: nil)
      @starts_at = starts_at
      @ends_at = ends_at
      @screen_ids = Array(screen_ids).compact.uniq
      @exclude_booking = exclude_booking
    end

    def call
      overlapping_bookings
    end

    private

    attr_reader :starts_at, :ends_at, :screen_ids, :exclude_booking

    def overlapping_bookings
      return AirtimeBooking.none if screen_ids.blank? || starts_at.blank? || ends_at.blank?

      scope = AirtimeBooking
        .confirmed
        .joins(broadcast_point_group: :broadcast_point_group_memberships)
        .where(broadcast_point_group_memberships: { screen_id: screen_ids })
        .where('airtime_bookings.starts_at < ? AND airtime_bookings.ends_at > ?', ends_at, starts_at)
        .distinct
      scope = scope.where.not(id: exclude_booking.id) if exclude_booking&.persisted?
      scope
    end
  end
end
