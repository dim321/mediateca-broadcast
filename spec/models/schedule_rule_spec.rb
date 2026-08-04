# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe ScheduleRule, type: :model do
  let(:organization) { create(:organization) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:point_group) { create(:point_group, organization: organization) }

  def build_rule(**attrs)
    org = attrs.delete(:organization) || organization
    pl = attrs.delete(:rotation) || rotation
    pg = attrs.delete(:point_group) || point_group
    attrs = {
      organization: org,
      rotation: pl,
      starts_at: Time.utc(2026, 7, 1, 10, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 12, 0, 0),
      timezone_context: :organization
    }.merge(attrs)
    rule = described_class.new(attrs.except(:point_group))
    rule.schedule_targets.build(point_group: pg)
    rule
  end

  it "requires ends_at after starts_at" do
    rule = build_rule(ends_at: Time.utc(2026, 7, 1, 9, 0, 0))
    expect(rule).not_to be_valid
    expect(rule.errors[:ends_at]).to be_present
  end

  it "requires rotation in the same organization" do
    other_rotation = create(:rotation)
    rule = build_rule(rotation: other_rotation)
    expect(rule).not_to be_valid
    expect(rule.errors[:rotation]).to be_present
  end

  it "rejects overlap on the same point group" do
    create(:schedule_rule,
      organization: organization,
      rotation: rotation,
      point_group: point_group,
      starts_at: Time.utc(2026, 7, 1, 10, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 12, 0, 0))

    overlapping = build_rule(
      starts_at: Time.utc(2026, 7, 1, 11, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 13, 0, 0)
    )
    expect(overlapping).not_to be_valid
    expect(overlapping.errors[:base]).to be_present
  end

  it "allows adjacent windows without overlap (half-open intervals)" do
    create(:schedule_rule,
      organization: organization,
      rotation: rotation,
      point_group: point_group,
      starts_at: Time.utc(2026, 7, 1, 10, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 12, 0, 0))

    adjacent = build_rule(
      starts_at: Time.utc(2026, 7, 1, 12, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 14, 0, 0)
    )
    expect(adjacent).to be_valid
  end

  it "allows updating itself without false overlap" do
    rule = create(:schedule_rule,
      organization: organization,
      rotation: rotation,
      point_group: point_group,
      starts_at: Time.utc(2026, 7, 1, 10, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 12, 0, 0))

    rule.schedule_targets.destroy_all
    rule.schedule_targets.build(point_group: point_group)
    rule.starts_at = Time.utc(2026, 7, 1, 10, 30, 0)
    rule.ends_at = Time.utc(2026, 7, 1, 11, 30, 0)
    expect(rule).to be_valid
  end

  it "requires at least one target" do
    rule = described_class.new(
      organization: organization,
      rotation: rotation,
      starts_at: Time.utc(2026, 7, 1, 10, 0, 0),
      ends_at: Time.utc(2026, 7, 1, 12, 0, 0),
      timezone_context: :organization
    )
    expect(rule).not_to be_valid
    expect(rule.errors[:base]).to be_present
  end

  it "parses local wall time via TimeWindowResolver" do
    org = build(:organization, time_zone: "Europe/Moscow")
    starts_utc, ends_utc = Scheduling::TimeWindowResolver.utc_range(
      organization: org,
      starts_at_param: "2026-06-01T12:00",
      ends_at_param: "2026-06-01T14:00"
    )
    expect(starts_utc).to eq(Time.find_zone!("Europe/Moscow").local(2026, 6, 1, 12, 0, 0).utc)
    expect(ends_utc).to eq(Time.find_zone!("Europe/Moscow").local(2026, 6, 1, 14, 0, 0).utc)
  end
end
