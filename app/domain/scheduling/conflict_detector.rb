# frozen_string_literal: true

module Scheduling
  class ConflictDetector < BaseService
    def initialize(organization:, starts_at:, ends_at:, point_group_ids:, exclude_schedule_rule: nil)
      @organization = organization
      @starts_at = starts_at
      @ends_at = ends_at
      @point_group_ids = Array(point_group_ids).compact.uniq
      @exclude_schedule_rule = exclude_schedule_rule
    end

    def call
      conflicting_rules
    end

    private

    attr_reader :organization, :starts_at, :ends_at, :point_group_ids, :exclude_schedule_rule

    def conflicting_rules
      return [] if point_group_ids.blank?
      return [] if starts_at.blank? || ends_at.blank?

      scope = ScheduleRule
        .where(organization_id: organization.id)
        .joins(:schedule_targets)
        .where(schedule_targets: { point_group_id: point_group_ids })
        .where("schedule_rules.starts_at < ? AND schedule_rules.ends_at > ?", ends_at, starts_at)
        .distinct
      scope = scope.where.not(id: exclude_schedule_rule.id) if exclude_schedule_rule&.persisted?
      scope.to_a
    end
  end
end
