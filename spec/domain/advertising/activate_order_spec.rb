# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ActivateOrder do
  let(:organization) { create(:organization, :client, time_zone: "UTC") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: asset,
      product_name: "Triumph"
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }

  def fill_grid!(group:, dates:, shows: 36, price: 1_000, order: self.order)
    Advertising::UpdateGrid.call(
      order: order,
      lines: [ {
        broadcast_point_group_id: group.id,
        price_per_day_cents: price,
        days: dates.map { |date| { date: date, shows: shows } }
      } ]
    )
  end

  def june_range
    Date.new(2026, 6, 3)..Date.new(2026, 6, 30)
  end

  it "collapses a consecutive chain into one window at shows/hours (AE4)" do
    fill_grid!(group: group, dates: june_range)

    result = described_class.call(order: order)

    expect(result.occupied_windows.size).to eq(1)
    expect(result.conflicted_windows).to be_empty
    plan = result.occupied_windows.first.plan
    expect(plan).to be_active
    expect(plan.shows_per_hour).to eq(3)
    expect(plan.starts_at).to eq(Time.utc(2026, 6, 3, 0, 0, 0))
    expect(plan.ends_at).to eq(Time.utc(2026, 7, 1, 0, 0, 0))
    expect(plan.advertising_order_line).to eq(order.advertising_order_lines.sole)
    expect(order.reload).to be_active
  end

  it "splits chains around days with zero operating hours" do
    weekdays = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::WEEKDAY_HOURS)
    fill_grid!(group: weekdays, dates: [ Date.new(2026, 6, 5), Date.new(2026, 6, 8) ])

    result = described_class.call(order: order)

    expect(result.occupied_windows.size).to eq(2)
    expect(result.occupied_windows.map { |window| [ window.starts_at, window.ends_at ] }).to eq([
      [ Time.utc(2026, 6, 5, 0, 0, 0), Time.utc(2026, 6, 6, 0, 0, 0) ],
      [ Time.utc(2026, 6, 8, 0, 0, 0), Time.utc(2026, 6, 9, 0, 0, 0) ]
    ])
  end

  it "keeps occupied windows when another window conflicts (AE5)" do
    fill_grid!(group: group, dates: [
      Date.new(2026, 6, 3), Date.new(2026, 6, 5), Date.new(2026, 6, 7)
    ])
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: create(:rotation, organization: organization),
      starts_at: Time.utc(2026, 6, 5, 0, 0, 0),
      ends_at: Time.utc(2026, 6, 6, 0, 0, 0)
    )

    result = described_class.call(order: order)

    expect(result.occupied_windows.size).to eq(2)
    expect(result.conflicted_windows.size).to eq(1)
    expect(order.reload).to be_active
    expect(order.media_plans.active.count).to eq(2)
    uncovered = Advertising::GridCoverage.call(order: order).unoccupied_days.map(&:date)
    expect(uncovered).to eq([ Date.new(2026, 6, 5) ])
  end

  it "is idempotent and only occupies uncovered days on retry" do
    fill_grid!(group: group, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5) ])
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: create(:rotation, organization: organization),
      starts_at: Time.utc(2026, 6, 5, 0, 0, 0),
      ends_at: Time.utc(2026, 6, 6, 0, 0, 0)
    )
    described_class.call(order: order)
    blocking = MediaPlan.active.find_by!(starts_at: Time.utc(2026, 6, 5, 0, 0, 0))
    Airtime::Cancel.call(plan: blocking)

    result = described_class.call(order: order.reload)

    expect(result.occupied_windows.size).to eq(1)
    expect(result.occupied_windows.first.starts_at).to eq(Time.utc(2026, 6, 5, 0, 0, 0))
    expect(order.media_plans.active.count).to eq(2)
  end

  it "builds DST windows from local midnights and keeps shows_per_hour" do
    organization.update!(time_zone: "Europe/Berlin")
    fill_grid!(group: group, dates: [ Date.new(2026, 3, 29) ])
    zone = Time.find_zone!("Europe/Berlin")

    result = described_class.call(order: order)

    window = result.occupied_windows.sole
    expect(window.starts_at).to eq(zone.local(2026, 3, 29).utc)
    expect(window.ends_at).to eq(zone.local(2026, 3, 30).utc)
    expect(window.plan.shows_per_hour).to eq(3)
  end

  it "builds a 25-hour local window on the autumn DST day" do
    organization.update!(time_zone: "Europe/Berlin")
    fill_grid!(group: group, dates: [ Date.new(2026, 10, 25) ])
    zone = Time.find_zone!("Europe/Berlin")

    result = described_class.call(order: order)

    window = result.occupied_windows.sole
    expect(window.ends_at - window.starts_at).to eq(25.hours)
    expect(window.starts_at).to eq(zone.local(2026, 10, 25).utc)
  end

  it "occupies a leap day as a single local-midnight window" do
    fill_grid!(group: group, dates: [ Date.new(2028, 2, 29) ])

    result = described_class.call(order: order)

    expect(result.occupied_windows.sole.starts_at).to eq(Time.utc(2028, 2, 29, 0, 0, 0))
    expect(result.occupied_windows.sole.ends_at).to eq(Time.utc(2028, 3, 1, 0, 0, 0))
  end

  it "aggregates commercial quota into one flag (AE6)" do
    owner = create(:organization, :client)
    owned = create_group_with_hours!(
      organization: owner,
      commercial_quota_percent: 10,
      commercial_quota_period: :hour
    )
    long_clip = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 240)
    commercial = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: long_clip,
      product_name: "Triumph",
      placement_kind: :commercial
    )
    fill_grid!(order: commercial, group: owned, dates: [ Date.new(2026, 6, 3) ], shows: 36)

    result = described_class.call(order: commercial)

    expect(result.occupied_windows.size).to eq(1)
    expect(result.quota_exceeded).to be(true)
    expect(commercial.reload).to be_active
  end

  it "reports a PlacementChannel error on the line instead of raising" do
    owner = create(:organization, :client)
    foreign = create_group_with_hours!(organization: owner)
    foreign.screens.first.update!(owner_organization: create(:organization, :client))
    commercial = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: asset,
      product_name: "Triumph",
      placement_kind: :commercial
    )
    fill_grid!(order: commercial, group: foreign, dates: [ Date.new(2026, 6, 3) ])

    result = described_class.call(order: commercial)

    expect(result.occupied_windows).to be_empty
    expect(result.conflicted_windows.size).to eq(1)
    expect(result.conflicted_windows.first.error).to match(/owner organization group|organization groups/)
    expect(commercial.reload).to be_draft
  end

  it "refuses activation when the clip is not broadcast-ready" do
    fill_grid!(group: group, dates: [ Date.new(2026, 6, 3) ])
    asset.update_column(:processing_status, "processing")

    expect { described_class.call(order: order) }.to raise_error(
      Advertising::Error,
      I18n.t("advertising.errors.clip_not_ready")
    )
    expect(order.reload).to be_draft
    expect(MediaPlan.count).to eq(0)
  end

  context "when concurrent activates race", :concurrency do
    it "lets only one overlapping window occupy the screens" do
      fill_grid!(group: group, dates: [ Date.new(2026, 6, 3) ])
      other = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_asset: asset,
        product_name: "Other"
      )
      fill_grid!(order: other, group: group, dates: [ Date.new(2026, 6, 3) ])

      ready = Queue.new
      go = Queue.new
      outcomes = Queue.new

      threads = [ order, other ].map do |target|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            result = described_class.call(order: target)
            outcomes << result.occupied_windows.size
          end
        end
      end

      2.times { ready.pop }
      2.times { go << true }
      threads.each(&:join)

      occupied = Array.new(2) { outcomes.pop }
      expect(occupied.sort).to eq([ 0, 1 ])
      expect(MediaPlan.active.count).to eq(1)
      expect(AirtimeBooking.confirmed.count).to eq(1)
    end
  end
end
