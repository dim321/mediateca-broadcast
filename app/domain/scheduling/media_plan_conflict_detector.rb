# frozen_string_literal: true

module Scheduling
  class MediaPlanConflictDetector < BaseService
    def initialize(starts_at:, ends_at:, screen_ids:, organization_id: nil, exclude_media_plan: nil)
      @starts_at = starts_at
      @ends_at = ends_at
      @screen_ids = Array(screen_ids).compact.uniq
      @organization_id = organization_id
      @exclude_media_plan = exclude_media_plan
    end

    def call
      conflicting_media_plans
    end

    private

    attr_reader :starts_at, :ends_at, :screen_ids, :organization_id, :exclude_media_plan

    def conflicting_media_plans
      return [] if screen_ids.blank? || starts_at.blank? || ends_at.blank?

      scope = MediaPlan
        .active
        .joins(broadcast_point_group: :broadcast_point_group_memberships)
        .where(broadcast_point_group_memberships: { screen_id: screen_ids })
        .where('media_plans.starts_at < ? AND media_plans.ends_at > ?', ends_at, starts_at)
        .distinct
      scope = scope.where(organization_id: organization_id) if organization_id.present?
      scope = scope.where.not(id: exclude_media_plan.id) if exclude_media_plan&.persisted?
      scope
    end
  end
end
