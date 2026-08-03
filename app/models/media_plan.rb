# frozen_string_literal: true

class MediaPlan < ApplicationRecord
  belongs_to :organization
  belongs_to :rotation
  belongs_to :broadcast_point_group

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts
  validate :rotation_matches_organization
  validate :broadcast_point_group_matches_organization
  validate :broadcast_point_group_has_screens
  validate :rotation_is_broadcast_ready
  validate :no_overlapping_media_plans

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end

  def rotation_matches_organization
    return if rotation.blank? || organization.blank?
    return if rotation.organization_id == organization_id

    errors.add(:rotation, :wrong_organization)
  end

  def broadcast_point_group_matches_organization
    return if broadcast_point_group.blank? || organization.blank?
    return if broadcast_point_group.organization_id == organization_id

    errors.add(:broadcast_point_group, :wrong_organization)
  end

  def broadcast_point_group_has_screens
    return if broadcast_point_group.blank?
    return if conflict_screen_ids.any?

    errors.add(:broadcast_point_group, :must_have_screens)
  end

  def rotation_is_broadcast_ready
    return if rotation.blank?
    return if rotation.ordered_items.all? { |item| item.media_asset.broadcast_ready? }

    errors.add(:rotation, :not_broadcast_ready)
  end

  def no_overlapping_media_plans
    return if broadcast_point_group.blank? || starts_at.blank? || ends_at.blank?
    return if conflict_screen_ids.blank?

    conflicts = Scheduling::MediaPlanConflictDetector.call(
      starts_at: starts_at,
      ends_at: ends_at,
      screen_ids: conflict_screen_ids,
      exclude_media_plan: persisted? ? self : nil
    )
    errors.add(:base, :overlaps_existing) if conflicts.any?
  end

  def conflict_screen_ids
    @conflict_screen_ids ||= broadcast_point_group.screen_ids
  end
end
