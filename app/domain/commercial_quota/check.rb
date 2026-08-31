# frozen_string_literal: true

module CommercialQuota
  Result = Data.define(:exceeded, :hours)

  # Soft check after successful occupy/reschedule. Never blocks placement (KTD2/KTD3).
  class Check < ServiceObject
    def initialize(plan:)
      @plan = plan
    end

    def call
      group = plan.broadcast_point_group
      return Result.new(exceeded: false, hours: []) unless plan.commercial?
      return Result.new(exceeded: false, hours: []) unless group.commercial_quota_configured?

      time_zone = group.organization.time_zone.presence || "UTC"
      exceeded_hours = touched_hour_starts.filter_map do |hour_start|
        allowance = HourlyAllowance.call(
          group: group,
          hour_start: hour_start,
          percent: group.commercial_quota_percent,
          time_zone: time_zone
        )
        consumption = Consumption.call(
          group: group,
          hour_start: hour_start,
          include_plan: plan
        )
        hour_start if consumption > allowance
      end

      Result.new(exceeded: exceeded_hours.any?, hours: exceeded_hours)
    end

    private

    attr_reader :plan

    def touched_hour_starts
      cursor = plan.starts_at.beginning_of_hour
      last = (plan.ends_at - 1.second).beginning_of_hour
      hours = []
      while cursor <= last
        hours << cursor
        cursor += 1.hour
      end
      hours
    end
  end
end
