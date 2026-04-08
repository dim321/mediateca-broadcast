# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduleTarget, type: :model do
  let(:organization) { create(:organization) }
  let(:playlist) { create(:playlist, organization: organization) }
  let(:point_group) { create(:point_group, organization: organization) }

  it "requires point group in the same organization as the schedule" do
    rule = create(:schedule_rule, organization: organization, playlist: playlist, point_group: point_group)
    foreign_group = create(:point_group)

    target = build(:schedule_target, schedule_rule: rule, point_group: foreign_group)
    expect(target).not_to be_valid
    expect(target.errors[:point_group]).to be_present
  end

  it "enforces one target row per group per schedule" do
    rule = create(:schedule_rule, organization: organization, playlist: playlist, point_group: point_group)

    dup = build(:schedule_target, schedule_rule: rule, point_group: point_group)
    expect(dup).not_to be_valid
    expect(dup.errors[:point_group_id]).to be_present
  end
end
