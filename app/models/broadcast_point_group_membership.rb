# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_point_group_memberships
#
#  id                       :bigint           not null, primary key
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#  screen_id                :bigint           not null
#
# Indexes
#
#  idx_on_broadcast_point_group_id_7614dd11c4            (broadcast_point_group_id)
#  index_broadcast_point_group_memberships_on_screen_id  (screen_id)
#  index_broadcast_point_group_memberships_unique        (broadcast_point_group_id,screen_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => cascade
#  fk_rails_...  (screen_id => screens.id)
#
class BroadcastPointGroupMembership < ApplicationRecord
  belongs_to :broadcast_point_group
  belongs_to :screen

  validates :screen_id, uniqueness: { scope: :broadcast_point_group_id }
  validate :no_media_plan_overlap_for_screen

  private

  def no_media_plan_overlap_for_screen
    return if screen.blank? || broadcast_point_group.blank?

    broadcast_point_group.media_plans.find_each do |media_plan|
      conflicts = Scheduling::MediaPlanConflictDetector.call(
        starts_at: media_plan.starts_at,
        ends_at: media_plan.ends_at,
        screen_ids: [ screen.id ],
        organization_id: broadcast_point_group.organization_id,
        exclude_media_plan: media_plan
      )
      if conflicts.any?
        errors.add(:screen, :overlaps_existing_media_plan)
        break
      end
    end
  end
end
