# frozen_string_literal: true

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
