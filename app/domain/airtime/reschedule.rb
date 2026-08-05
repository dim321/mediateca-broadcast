# frozen_string_literal: true

module Airtime
  # In-place move; on failure the transaction rolls back (AE3 / KTD4).
  class Reschedule < BaseService
    def initialize(booking:, quota:, starts_at:, ends_at:)
      @booking = booking
      @quota = quota
      @starts_at = starts_at
      @ends_at = ends_at
    end

    def call
      validate_inputs!
      new_seconds = (ends_at - starts_at).to_i

      AirtimeBooking.transaction do
        locked = AirtimeBooking.lock.find(booking.id)
        raise ArgumentError, 'cannot reschedule cancelled booking' if locked.cancelled?

        old_group = locked.broadcast_point_group
        new_group = quota.broadcast_point_group
        raise ArgumentError, 'organization must own the target group' unless new_group.organization_id == locked.organization_id

        screen_ids = (old_group.screen_ids + new_group.screen_ids).uniq
        ScreenLock.call(screen_ids: screen_ids)

        quota_ids = [ locked.airtime_quota_id, quota.id ].uniq.sort
        locked_quotas = AirtimeQuota.lock.where(id: quota_ids).index_by(&:id)
        old_quota = locked_quotas.fetch(locked.airtime_quota_id)
        new_quota = locked_quotas.fetch(quota.id)

        if ScreenOverlapGuard.call(
          starts_at: starts_at,
          ends_at: ends_at,
          screen_ids: new_group.screen_ids,
          exclude_booking: locked
        ).exists?
          raise Airtime::ConflictError, 'target screen slot already booked'
        end

        apply_quota_delta!(old_quota:, new_quota:, old_seconds: locked.seconds, new_seconds:)

        locked.update!(
          airtime_quota: new_quota,
          broadcast_point_group: new_group,
          starts_at: starts_at,
          ends_at: ends_at,
          seconds: new_seconds
        )

        invalidate_incompatible_plans!(locked)
        locked
      end
    end

    private

    attr_reader :booking, :quota, :starts_at, :ends_at

    def validate_inputs!
      raise Airtime::InvalidWindowError, 'starts_at and ends_at required' if starts_at.blank? || ends_at.blank?
      raise Airtime::InvalidWindowError, 'ends_at must be after starts_at' unless ends_at > starts_at
      raise Airtime::InvalidWindowError, 'booking must fit inside quota window' unless quota.covers?(starts_at, ends_at)
      raise ArgumentError, 'target group must include at least one screen' if quota.broadcast_point_group.screen_ids.empty?
    end

    def apply_quota_delta!(old_quota:, new_quota:, old_seconds:, new_seconds:)
      if old_quota.id == new_quota.id
        delta = new_seconds - old_seconds
        remaining = old_quota.seconds_remaining - delta
        raise Airtime::OverflowError, 'insufficient quota remaining' if remaining.negative?

        old_quota.update!(seconds_remaining: remaining)
      else
        raise Airtime::OverflowError, 'insufficient quota remaining' if new_quota.seconds_remaining < new_seconds

        old_quota.update!(seconds_remaining: old_quota.seconds_remaining + old_seconds)
        new_quota.update!(seconds_remaining: new_quota.seconds_remaining - new_seconds)
      end
    end

    def invalidate_incompatible_plans!(locked_booking)
      locked_booking.media_plans.active.find_each do |plan|
        next if locked_booking.covers_plan?(plan)

        # Skip validations: plan window is intentionally outside the new booking (KTD4).
        plan.update_columns(status: MediaPlan.statuses[:invalidated], updated_at: Time.current)
      end
    end
  end
end
