# frozen_string_literal: true

module Airtime
  # Confirmed bookings must not overlap on shared screens (R6).
  # Two advertising-order claims may share a screen and window.
  class ScreenOverlapGuard < BaseService
    def initialize(starts_at:, ends_at:, screen_ids:, exclude_booking: nil, order_claim: false)
      @starts_at = starts_at
      @ends_at = ends_at
      @screen_ids = Array(screen_ids).compact.uniq
      @exclude_booking = exclude_booking
      @order_claim = order_claim
    end

    def call
      overlapping_bookings
    end

    private

    attr_reader :starts_at, :ends_at, :screen_ids, :exclude_booking, :order_claim

    def overlapping_bookings
      return AirtimeBooking.none if screen_ids.blank? || starts_at.blank? || ends_at.blank?

      scope = AirtimeBooking
        .confirmed
        .left_outer_joins(broadcast_point_group: :broadcast_point_group_memberships)
        .left_outer_joins(media_plans: :media_plan_screens)
        .where(
          "broadcast_point_group_memberships.screen_id IN (:ids) OR media_plan_screens.screen_id IN (:ids)",
          ids: screen_ids
        )
        .where("airtime_bookings.starts_at < ? AND airtime_bookings.ends_at > ?", ends_at, starts_at)
        .distinct
      scope = scope.where("media_plans.advertising_order_line_id IS NULL") if order_claim
      scope = scope.where.not(id: exclude_booking.id) if exclude_booking&.persisted?
      scope
    end
  end
end
