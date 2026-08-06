# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent::PackageBuilder do
  describe '.call' do
    it 'includes plans intersecting the station offline-cache horizon with booking metadata' do
      client = create(:organization, :client)
      station = create(:station, offline_cache_hours: 24)
      screen = create(:screen, station:)
      plan = create_plan(client:, screen:, starts_at: 12.hours.from_now, ends_at: 36.hours.from_now)

      package = described_class.call(station:, now: Time.current)

      expect(package[:items]).to contain_exactly(
        include(
          media_plan_id: plan.id,
          organization_id: client.id,
          airtime_booking_id: plan.airtime_booking_id,
          screen_ids: [ screen.id ]
        )
      )
      expect(package[:screen_map]).to eq(screen.id.to_s => [ plan.id ])
    end

    it 'includes two orgs plans on the same screen (AE6)' do
      station = create(:station, offline_cache_hours: 24)
      screen = create(:screen, station:)
      org_a = create(:organization, :client)
      org_b = create(:organization, :client)
      plan_a = create_plan(
        client: org_a,
        screen:,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 10, 30, 0)
      )
      plan_b = create_plan(
        client: org_b,
        screen:,
        starts_at: Time.utc(2026, 8, 10, 10, 30, 0),
        ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
      )

      package = described_class.call(station:, now: Time.utc(2026, 8, 10, 9, 0, 0))

      expect(package[:items].map { |i| i[:media_plan_id] }).to contain_exactly(plan_a.id, plan_b.id)
      expect(package[:items].map { |i| i[:organization_id] }).to contain_exactly(org_a.id, org_b.id)
    end

    it 'excludes invalidated plans and cancelled bookings' do
      client = create(:organization, :client)
      station = create(:station, offline_cache_hours: 24)
      screen = create(:screen, station:)
      plan = create_plan(client:, screen:, starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
      plan.update_columns(status: MediaPlan.statuses[:invalidated], updated_at: Time.current)

      package = described_class.call(station:, now: Time.current)

      expect(package[:items]).to be_empty
    end

    it 'excludes soft-cancelled plans from the package' do
      client = create(:organization, :client)
      station = create(:station, offline_cache_hours: 24)
      screen = create(:screen, station:)
      plan = create_plan(client:, screen:, starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
      Airtime::Cancel.call(plan: plan)

      package = described_class.call(station:, now: Time.current)

      expect(package[:items]).to be_empty
    end
  end

  private

  def create_plan(client:, screen:, starts_at:, ends_at:)
    rotation = create(:rotation, organization: client)
    media_asset = create(:media_asset, :ready, :with_png_file, organization: client)
    create(:rotation_item, rotation:, media_asset:, position: 1)
    group = create(:broadcast_point_group, organization: client)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen:)
    create(:media_plan, organization: client, rotation:, broadcast_point_group: group, starts_at:, ends_at:)
  end
end
