# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe ScheduleTarget, type: :model do
  let(:organization) { create(:organization) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:point_group) { create(:point_group, organization: organization) }

  it "requires point group in the same organization as the schedule" do
    rule = create(:schedule_rule, organization: organization, rotation: rotation, point_group: point_group)
    foreign_group = create(:point_group)

    target = build(:schedule_target, schedule_rule: rule, point_group: foreign_group)
    expect(target).not_to be_valid
    expect(target.errors[:point_group]).to be_present
  end

  it "enforces one target row per group per schedule" do
    rule = create(:schedule_rule, organization: organization, rotation: rotation, point_group: point_group)

    dup = build(:schedule_target, schedule_rule: rule, point_group: point_group)
    expect(dup).not_to be_valid
    expect(dup.errors[:point_group_id]).to be_present
  end
end
