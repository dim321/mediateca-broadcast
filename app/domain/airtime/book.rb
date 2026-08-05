# frozen_string_literal: true

module Airtime
  class Book < BaseService
    def initialize(quota:, organization:, starts_at:, ends_at:)
      @quota = quota
      @organization = organization
      @starts_at = starts_at
      @ends_at = ends_at
    end

    def call
      validate_inputs!
      seconds = booking_seconds

      AirtimeBooking.transaction do
        screen_ids = group.screen_ids
        ScreenLock.call(screen_ids: screen_ids)

        locked_quota = AirtimeQuota.lock.find(quota.id)
          raise Airtime::OverflowError, 'insufficient quota remaining' if locked_quota.seconds_remaining < seconds

        if ScreenOverlapGuard.call(starts_at: starts_at, ends_at: ends_at, screen_ids: screen_ids).exists?
          raise Airtime::ConflictError, 'screen slot already booked'
        end

        locked_quota.update!(seconds_remaining: locked_quota.seconds_remaining - seconds)

        AirtimeBooking.create!(
          airtime_quota: locked_quota,
          organization: organization,
          broadcast_point_group: group,
          starts_at: starts_at,
          ends_at: ends_at,
          seconds: seconds,
          status: :confirmed
        )
      end
    end

    private

    attr_reader :quota, :organization, :starts_at, :ends_at

    def group
      @group ||= quota.broadcast_point_group
    end

    def validate_inputs!
      raise Airtime::InvalidWindowError, 'starts_at and ends_at required' if starts_at.blank? || ends_at.blank?
      raise Airtime::InvalidWindowError, 'ends_at must be after starts_at' unless ends_at > starts_at
      raise Airtime::InvalidWindowError, 'booking must fit inside quota window' unless quota.covers?(starts_at, ends_at)
      raise ArgumentError, 'organization must own the broadcast point group' unless group.organization_id == organization.id
      raise ArgumentError, 'group must include at least one screen' if group.screen_ids.empty?
    end

    def booking_seconds
      (ends_at - starts_at).to_i
    end
  end
end
