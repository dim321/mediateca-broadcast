# frozen_string_literal: true

# == Schema Information
#
# Table name: schedule_rules
#
#  id               :bigint           not null, primary key
#  ends_at          :datetime         not null
#  starts_at        :datetime         not null
#  timezone_context :string           default("organization"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :bigint           not null
#  rotation_id      :bigint           not null
#
# Indexes
#
#  idx_on_organization_id_starts_at_ends_at_962bcc92ff      (organization_id,starts_at,ends_at)
#  index_schedule_rules_on_organization_id                  (organization_id)
#  index_schedule_rules_on_organization_id_and_rotation_id  (organization_id,rotation_id)
#  index_schedule_rules_on_rotation_id                      (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
class ScheduleRule < ApplicationRecord
  belongs_to :organization
  belongs_to :rotation

  has_many :schedule_targets, dependent: :destroy
  has_many :point_groups, through: :schedule_targets

  enum :timezone_context, {
    organization: "organization",
    point: "point"
  }, validate: true

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts
  validate :rotation_matches_organization
  validate :at_least_one_target
  validate :no_overlapping_schedules

  def selected_point_group_ids
    schedule_targets.map(&:point_group_id).compact.uniq
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end

  def rotation_matches_organization
    return unless rotation && organization

    return if rotation.organization_id == organization_id

    errors.add(:rotation, :wrong_organization)
  end

  def at_least_one_target
    return if schedule_targets.reject(&:marked_for_destruction?).any?

    errors.add(:base, :must_have_targets)
  end

  def no_overlapping_schedules
    ids = schedule_targets.reject(&:marked_for_destruction?).map(&:point_group_id).compact.uniq
    return if ids.empty? || starts_at.blank? || ends_at.blank?

    conflicts = Scheduling::ConflictDetector.call(
      organization: organization,
      starts_at: starts_at,
      ends_at: ends_at,
      point_group_ids: ids,
      exclude_schedule_rule: persisted? ? self : nil
    )
    return if conflicts.empty?

    errors.add(:base, :overlaps_existing)
  end
end
