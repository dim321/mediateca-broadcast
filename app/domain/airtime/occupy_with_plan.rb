# frozen_string_literal: true

module Airtime
  # Atomically occupy a calendar slot and attach an active MediaPlan (KTD3).
  class OccupyWithPlan < BaseService
    def initialize(
      organization:,
      broadcast_point_group:,
      rotation:,
      starts_at:,
      ends_at:,
      placement_kind: :own_atmosphere,
      shows_per_hour: nil
    )
      @organization = organization
      @broadcast_point_group = broadcast_point_group
      @rotation = rotation
      @starts_at = starts_at
      @ends_at = ends_at
      @placement_kind = placement_kind
      @shows_per_hour = shows_per_hour
    end

    def call
      validate_inputs!
      seconds = booking_seconds

      MediaPlan.transaction do
        ScreenLock.call(screen_ids: screen_ids)

        if ScreenOverlapGuard.call(starts_at: starts_at, ends_at: ends_at, screen_ids: screen_ids).exists?
          raise Airtime::ConflictError, "screen slot already booked"
        end

        booking = AirtimeBooking.create!(
          organization: organization,
          broadcast_point_group: broadcast_point_group,
          starts_at: starts_at,
          ends_at: ends_at,
          seconds: seconds,
          status: :confirmed
        )

        MediaPlan.create!(
          organization: organization,
          broadcast_point_group: broadcast_point_group,
          rotation: rotation,
          airtime_booking: booking,
          starts_at: starts_at,
          ends_at: ends_at,
          status: :active,
          placement_kind: placement_kind,
          shows_per_hour: shows_per_hour
        )
      end
    end

    private

    attr_reader :organization, :broadcast_point_group, :rotation, :starts_at, :ends_at,
      :placement_kind, :shows_per_hour

    def validate_inputs!
      validate_time_window!
      PlacementChannel.assert!(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        placement_kind: placement_kind
      )
      raise ArgumentError, "organization must own the rotation" unless rotation.organization_id == organization.id
      raise ArgumentError, "group must include at least one screen" if screen_ids.empty?
    end

    def screen_ids
      @screen_ids ||= broadcast_point_group.screen_ids
    end
  end
end
