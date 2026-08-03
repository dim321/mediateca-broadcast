# frozen_string_literal: true

class BroadcastPointGroupMembership < ApplicationRecord
  belongs_to :broadcast_point_group
  belongs_to :screen

  validates :screen_id, uniqueness: { scope: :broadcast_point_group_id }
  validate :screen_from_operator_catalog
  validate :no_media_plan_overlap_for_screen

  private

  def screen_from_operator_catalog
    return if screen.blank?
    return if screen.organization&.operator?

    errors.add(:screen, :not_in_operator_catalog)
  end

  def no_media_plan_overlap_for_screen
    return if screen.blank? || broadcast_point_group.blank?

    broadcast_point_group.media_plans.find_each do |media_plan|
      conflicts = Scheduling::MediaPlanConflictDetector.call(
        starts_at: media_plan.starts_at,
        ends_at: media_plan.ends_at,
        screen_ids: [ screen.id ],
        exclude_media_plan: media_plan
      )
      if conflicts.any?
        errors.add(:screen, :overlaps_existing_media_plan)
        break
      end
    end
  end
end
