# frozen_string_literal: true

# == Schema Information
#
# Table name: schedule_targets
#
#  id               :bigint           not null, primary key
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  point_group_id   :bigint           not null
#  schedule_rule_id :bigint           not null
#
# Indexes
#
#  index_schedule_targets_on_point_group_id    (point_group_id)
#  index_schedule_targets_on_schedule_rule_id  (schedule_rule_id)
#  index_schedule_targets_unique               (schedule_rule_id,point_group_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (point_group_id => point_groups.id)
#  fk_rails_...  (schedule_rule_id => schedule_rules.id) ON DELETE => cascade
#
class ScheduleTarget < ApplicationRecord
  belongs_to :schedule_rule
  belongs_to :point_group

  validates :point_group_id, uniqueness: { scope: :schedule_rule_id }
  validate :same_organization_as_schedule

  private

  def same_organization_as_schedule
    return unless schedule_rule && point_group

    if point_group.organization_id != schedule_rule.organization_id
      errors.add(:point_group, :wrong_organization)
    end
  end
end
