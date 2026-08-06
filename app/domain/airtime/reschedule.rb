# frozen_string_literal: true

module Airtime
  # In-place move of plan + internal booking; on failure ROLLBACK (KTD4 / AE3).
  class Reschedule < BaseService
    def initialize(plan:, broadcast_point_group:, starts_at:, ends_at:)
      @plan = plan
      @broadcast_point_group = broadcast_point_group
      @starts_at = starts_at
      @ends_at = ends_at
    end

    def call
      validate_inputs!
      new_seconds = (ends_at - starts_at).to_i

      MediaPlan.transaction do
        locked_plan = MediaPlan.lock.find(plan.id)
        raise ArgumentError, 'cannot reschedule cancelled plan' if locked_plan.cancelled?
        raise ArgumentError, 'cannot reschedule invalidated plan' if locked_plan.invalidated?

        locked_booking = AirtimeBooking.lock.find(locked_plan.airtime_booking_id)
        raise ArgumentError, 'cannot reschedule cancelled booking' if locked_booking.cancelled?

        old_group = locked_booking.broadcast_point_group
        new_group = broadcast_point_group
        raise ArgumentError, 'organization must own the target group' unless new_group.organization_id == locked_plan.organization_id

        screen_ids = (old_group.screen_ids + new_group.screen_ids).uniq
        ScreenLock.call(screen_ids: screen_ids)

        if ScreenOverlapGuard.call(
          starts_at: starts_at,
          ends_at: ends_at,
          screen_ids: new_group.screen_ids,
          exclude_booking: locked_booking
        ).exists?
          raise Airtime::ConflictError, 'target screen slot already booked'
        end

        locked_booking.update!(
          broadcast_point_group: new_group,
          starts_at: starts_at,
          ends_at: ends_at,
          seconds: new_seconds
        )

        locked_plan.update!(
          broadcast_point_group: new_group,
          starts_at: starts_at,
          ends_at: ends_at
        )

        locked_plan
      end
    end

    private

    attr_reader :plan, :broadcast_point_group, :starts_at, :ends_at

    def validate_inputs!
      raise Airtime::InvalidWindowError, 'starts_at and ends_at required' if starts_at.blank? || ends_at.blank?
      raise Airtime::InvalidWindowError, 'ends_at must be after starts_at' unless ends_at > starts_at
      raise ArgumentError, 'target group must include at least one screen' if broadcast_point_group.screen_ids.empty?
    end
  end
end
