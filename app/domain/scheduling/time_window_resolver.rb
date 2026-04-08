# frozen_string_literal: true

module Scheduling
  class TimeWindowResolver
    def self.utc_range(organization:, starts_at_param:, ends_at_param:)
      zone = Time.find_zone!(organization.time_zone.to_s)
      start_local = zone.parse(starts_at_param.to_s)
      end_local = zone.parse(ends_at_param.to_s)
      raise ArgumentError if start_local.nil? || end_local.nil?

      [ start_local.utc, end_local.utc ]
    end
  end
end
