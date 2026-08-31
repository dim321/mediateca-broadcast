# frozen_string_literal: true

module CommercialQuota
  # Sum of N × cycle duration for active commercial plans overlapping the hour on the group.
  # Soft MVP: no screen-timeline overlap accounting (R13).
  class Consumption < ServiceObject
    def initialize(group:, hour_start:, exclude_plan: nil, include_plan: nil)
      @group = group
      @hour_start = hour_start
      @exclude_plan = exclude_plan
      @include_plan = include_plan
    end

    def call
      hour_end = hour_start + 1.hour
      plans = overlapping_commercial_plans(hour_end)
      if include_plan && plans.none? { |plan| same_plan?(plan, include_plan) }
        plans << include_plan
      end

      plans.sum { |plan| plan_seconds(plan) }
    end

    private

    attr_reader :group, :hour_start, :exclude_plan, :include_plan

    def same_plan?(left, right)
      return left.equal?(right) unless left.persisted? && right.persisted?

      left.id == right.id
    end
    def overlapping_commercial_plans(hour_end)
      scope = group.media_plans.active.commercial
        .where("starts_at < ? AND ends_at > ?", hour_end, hour_start)
      scope = scope.where.not(id: exclude_plan.id) if exclude_plan&.persisted?
      scope.to_a
    end

    def plan_seconds(plan)
      n = plan.shows_per_hour.to_i
      return 0 if n < 1

      n * CycleDuration.call(rotation: plan.rotation)
    end
  end
end
