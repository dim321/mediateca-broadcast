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
      new_seconds = booking_seconds

      MediaPlan.transaction do
        locked_plan = MediaPlan.lock.find(plan.id)
        raise ArgumentError, 'cannot reschedule cancelled plan' if locked_plan.cancelled?
        raise ArgumentError, 'cannot reschedule invalidated plan' if locked_plan.invalidated?

        locked_booking = AirtimeBooking.lock.find(locked_plan.airtime_booking_id)
        raise ArgumentError, 'cannot reschedule cancelled booking' if locked_booking.cancelled?

        old_group = locked_booking.broadcast_point_group
        new_group = broadcast_point_group
        raise ArgumentError, 'organization must own the target group' unless new_group.organization_id == locked_plan.organization_id

        lock_screen_ids = if old_group.id == new_group.id
          old_group.screen_ids
        else
          (old_group.screen_ids + new_group.screen_ids).uniq
        end
        ScreenLock.call(screen_ids: lock_screen_ids)

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

        # Window/group move is occupancy-only; do not re-run rotation readiness
        # validations that can block a free-target reschedule (KTD4 / AE3).
        locked_plan.assign_attributes(
          broadcast_point_group: new_group,
          starts_at: starts_at,
          ends_at: ends_at
        )
        locked_plan.save!(validate: false)

        locked_plan
      end
    end

    private

    attr_reader :plan, :broadcast_point_group, :starts_at, :ends_at

    def validate_inputs!
      validate_time_window!
      raise ArgumentError, 'target group must include at least one screen' if broadcast_point_group.screen_ids.empty?
    end
  end
end
