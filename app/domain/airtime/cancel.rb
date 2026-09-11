# frozen_string_literal: true

module Airtime
  # Soft-cancel a media plan and its internal booking together (KTD5).
  class Cancel < BaseService
    def initialize(plan:)
      @plan = plan
    end

    def call
      cancelled = MediaPlan.transaction do
        locked_plan = MediaPlan.lock.find(plan.id)
        raise ArgumentError, "plan already cancelled" if locked_plan.cancelled?

        locked_booking = AirtimeBooking.lock.find(locked_plan.airtime_booking_id)
        ScreenLock.call(screen_ids: occupying_screen_ids(locked_plan, locked_booking))

        # Skip full AR validations: cancel must free the slot even if rotation/media
        # later became not broadcast-ready or the group lost screens.
        locked_plan.update_columns(
          status: MediaPlan.statuses[:cancelled],
          updated_at: Time.current
        )
        unless locked_booking.cancelled?
          locked_booking.update_columns(
            status: AirtimeBooking.statuses[:cancelled],
            updated_at: Time.current
          )
        end

        locked_plan
      end
      Playlists::EnqueueRegen.from_plan(cancelled)
      cancelled
    end

    private

    attr_reader :plan

    def occupying_screen_ids(locked_plan, locked_booking)
      ids = locked_plan.screens.ids
      return ids if ids.any?

      Array(locked_booking.broadcast_point_group&.screen_ids)
    end
  end
end
