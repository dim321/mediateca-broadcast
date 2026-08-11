# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommercialQuota::Check do
  let(:owner) { create(:organization, :client, time_zone: "UTC") }
  let(:location) do
    create(
      :location,
      operating_hours: { "mon" => [ { "start" => "10:00", "end" => "11:00" } ] }
    )
  end
  let(:screen) do
    create(:screen, station: create(:station, location: location), owner_organization: owner)
  end
  let(:group) do
    create(:broadcast_point_group, organization: owner).tap do |g|
      create(:broadcast_point_group_membership, broadcast_point_group: g, screen: screen)
      g.update!(commercial_quota_percent: 60, commercial_quota_period: :hour)
    end
  end
  let(:rotation) { create(:rotation, organization: owner) }

  before do
    asset = create(:media_asset, :ready, :with_png_file, organization: owner)
    create(:rotation_item, rotation: rotation, media_asset: asset, display_duration_seconds: 240)
  end

  def create_commercial!(shows:, starts_at:, ends_at:, org: owner, rot: rotation)
    create(
      :media_plan,
      organization: org,
      rotation: rot,
      broadcast_point_group: group,
      placement_kind: :commercial,
      shows_per_hour: shows,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  it "flags exceed for AE1 numbers (20+40 > 36)" do
    create_commercial!(
      shows: 5,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 30, 0)
    )

    candidate = create_commercial!(
      shows: 10,
      starts_at: Time.utc(2026, 8, 10, 10, 30, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
    )

    result = described_class.call(plan: candidate)

    expect(result.exceeded).to be(true)
    expect(result.hours).to include(Time.utc(2026, 8, 10, 10, 0, 0))
  end

  it "still checks per hour when period is day (AE2)" do
    group.update!(commercial_quota_period: :day)
    create_commercial!(
      shows: 5,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 30, 0)
    )
    candidate = create_commercial!(
      shows: 10,
      starts_at: Time.utc(2026, 8, 10, 10, 30, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
    )

    result = described_class.call(plan: candidate)

    expect(result.exceeded).to be(true)
    expect(result.hours.size).to be >= 1
  end

  it "excludes own_atmosphere from the numerator (AE5)" do
    create_commercial!(
      shows: 9,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 30, 0)
    )

    atmosphere = create(
      :media_plan,
      organization: owner,
      rotation: rotation,
      broadcast_point_group: group,
      placement_kind: :own_atmosphere,
      starts_at: Time.utc(2026, 8, 10, 10, 30, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
    )

    result = described_class.call(plan: atmosphere)

    expect(result.exceeded).to be(false)
  end

  it "does not warn when no quota is configured" do
    group.update!(commercial_quota_percent: nil, commercial_quota_period: nil)
    plan = create_commercial!(
      shows: 100,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
    )

    expect(described_class.call(plan: plan).exceeded).to be(false)
  end
end
