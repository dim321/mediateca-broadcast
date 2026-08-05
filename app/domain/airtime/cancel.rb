# frozen_string_literal: true

module Airtime
  class Cancel < BaseService
    def initialize(booking:)
      @booking = booking
    end

    def call
      AirtimeBooking.transaction do
        locked = AirtimeBooking.lock.find(booking.id)
        raise ArgumentError, 'booking already cancelled' if locked.cancelled?

        # R7 / KTD5 — full association gate; U5 strengthens MediaPlan create path.
        if locked.media_plans.active.exists?
          raise Airtime::CancelBlockedError, 'cancel blocked while media plan is linked'
        end

        ScreenLock.call(screen_ids: locked.broadcast_point_group.screen_ids)
        quota = AirtimeQuota.lock.find(locked.airtime_quota_id)
        quota.update!(seconds_remaining: quota.seconds_remaining + locked.seconds)
        locked.update!(status: :cancelled)
        locked
      end
    end

    private

    attr_reader :booking
  end
end
