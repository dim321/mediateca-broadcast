# frozen_string_literal: true

module Airtime
  # Occupied windows for LK: start/end only — no foreign booking/org ids (R2).
  class OccupancyPresenter < BaseService
    def initialize(broadcast_point_group:, exclude_booking: nil)
      @broadcast_point_group = broadcast_point_group
      @exclude_booking = exclude_booking
    end

    def call
      screen_ids = broadcast_point_group.screen_ids
      return [] if screen_ids.blank?

      scope = AirtimeBooking
        .confirmed
        .joins(broadcast_point_group: :broadcast_point_group_memberships)
        .where(broadcast_point_group_memberships: { screen_id: screen_ids })
        .distinct
        .order(:starts_at)
      scope = scope.where.not(id: exclude_booking.id) if exclude_booking&.persisted?

      scope.pluck(:starts_at, :ends_at).map do |starts_at, ends_at|
        { starts_at: starts_at, ends_at: ends_at, occupied: true }
      end
    end

    private

    attr_reader :broadcast_point_group, :exclude_booking
  end
end
