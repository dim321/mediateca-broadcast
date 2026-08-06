# frozen_string_literal: true

module Airtime
  # Soft-cancel a media plan and its internal booking together (KTD5).
  class Cancel < BaseService
    def initialize(plan:)
      @plan = plan
    end

    def call
      MediaPlan.transaction do
        locked_plan = MediaPlan.lock.find(plan.id)
        raise ArgumentError, 'plan already cancelled' if locked_plan.cancelled?

        locked_booking = AirtimeBooking.lock.find(locked_plan.airtime_booking_id)
        ScreenLock.call(screen_ids: locked_booking.broadcast_point_group.screen_ids)

        locked_plan.update!(status: :cancelled)
        locked_booking.update!(status: :cancelled) unless locked_booking.cancelled?

        locked_plan
      end
    end

    private

    attr_reader :plan
  end
end
