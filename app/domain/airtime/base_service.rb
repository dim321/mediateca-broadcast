# frozen_string_literal: true

module Airtime
  class BaseService < ServiceObject
    private

    def validate_time_window!
      raise Airtime::InvalidWindowError, "starts_at and ends_at required" if starts_at.blank? || ends_at.blank?
      raise Airtime::InvalidWindowError, "ends_at must be after starts_at" unless ends_at > starts_at
    end

    def booking_seconds
      (ends_at - starts_at).to_i
    end
  end
end
