# frozen_string_literal: true

module Airtime
  # Atomically occupy a calendar slot and attach an active MediaPlan (KTD3).
  class OccupyWithPlan < BaseService
    def initialize(
      organization:,
      rotation:,
      starts_at:,
      ends_at:,
      broadcast_point_group: nil,
      screens: nil,
      placement_kind: :own_atmosphere,
      shows_per_hour: nil,
      order_claim: false,
      advertising_order_line: nil
    )
      @organization = organization
      @broadcast_point_group = broadcast_point_group
      @screens = screens
      @rotation = rotation
      @starts_at = starts_at
      @ends_at = ends_at
      @placement_kind = placement_kind
      @shows_per_hour = shows_per_hour
      @order_claim = order_claim
      @advertising_order_line = advertising_order_line
    end

    def call
      validate_inputs!
      seconds = booking_seconds

      plan = MediaPlan.transaction do
        ScreenLock.call(screen_ids: screen_ids)

        if ScreenOverlapGuard.call(
          starts_at: starts_at,
          ends_at: ends_at,
          screen_ids: screen_ids,
          order_claim: order_claim
        ).exists?
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

        record = MediaPlan.new(
          organization: organization,
          broadcast_point_group: broadcast_point_group,
          rotation: rotation,
          airtime_booking: booking,
          starts_at: starts_at,
          ends_at: ends_at,
          status: :active,
          placement_kind: placement_kind,
          shows_per_hour: shows_per_hour,
          advertising_order_line: advertising_order_line
        )
        occupy_screens.each { |screen| record.media_plan_screens.build(screen: screen) }
        record.save!
        record
      end
      Playlists::EnqueueRegen.from_plan(plan)
      plan
    end

    private

    attr_reader :organization, :broadcast_point_group, :screens, :rotation, :starts_at, :ends_at,
      :placement_kind, :shows_per_hour, :order_claim, :advertising_order_line

    def validate_inputs!
      validate_time_window!
      assert_placement_channel!
      raise ArgumentError, "organization must own the rotation" unless rotation.organization_id == organization.id
      raise ArgumentError, "group must include at least one screen" if screen_ids.empty?
    end

    def assert_placement_channel!
      if broadcast_point_group
        PlacementChannel.assert!(
          organization: organization,
          broadcast_point_group: broadcast_point_group,
          placement_kind: placement_kind
        )
      else
        PlacementChannel.assert_screens!(
          organization: organization,
          screens: occupy_screens,
          placement_kind: placement_kind
        )
      end
    end

    def occupy_screens
      @occupy_screens ||= if screens.nil?
        Array(broadcast_point_group&.screens)
      else
        Array(screens).map { |item| item.is_a?(Screen) ? item : Screen.find(item) }
      end
    end

    def screen_ids
      occupy_screens.map(&:id)
    end
  end
end
