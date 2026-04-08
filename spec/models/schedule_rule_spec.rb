# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduleRule, type: :model do
  let(:organization) { create(:organization) }
  let(:playlist) { create(:playlist, organization: organization) }
  let(:point_group) { create(:point_group, organization: organization) }

  def build_rule(**attrs)
    org = attrs.delete(:organization) || organization
    pl = attrs.delete(:playlist) || playlist
    pg = attrs.delete(:point_group) || point_group
    attrs = {
      organization: org,
      playlist: pl,
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

  it "requires playlist in the same organization" do
    other_playlist = create(:playlist)
    rule = build_rule(playlist: other_playlist)
    expect(rule).not_to be_valid
    expect(rule.errors[:playlist]).to be_present
  end

  it "rejects overlap on the same point group" do
    create(:schedule_rule,
      organization: organization,
      playlist: playlist,
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
      playlist: playlist,
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
      playlist: playlist,
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
      playlist: playlist,
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
