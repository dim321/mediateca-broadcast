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
      media_assets: [ asset ],
      product_name: "Triumph",
      shows_per_hour: 3
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }
  let(:screen) { group.screens.first }

  def setup_order!(order:, screen: self.screen, dates:, shows: 9, **window_attrs)
    fill_order_grid!(order, screen: screen, dates: dates, shows: shows, **window_attrs)
  end

  it "lets two orders claim the same screen and window" do
    setup_order!(order: order, dates: [ Date.new(2026, 6, 3) ])
    other = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Other",
      shows_per_hour: 3
    )
    setup_order!(order: other, dates: [ Date.new(2026, 6, 3) ])

    first = described_class.call(order: order)
    second = described_class.call(order: other)

    expect(first.conflicted_windows).to be_empty
    expect(second.conflicted_windows).to be_empty
    expect(MediaPlan.active.count).to eq(2)
    expect(MediaPlan.active.flat_map { |plan| plan.screens.to_a }.uniq).to eq([ screen ])
  end

  it "occupies each intersecting window as its own claim" do
    setup_order!(
      order: order,
      dates: [ Date.new(2026, 6, 3) ],
      windows: [
        { starts_at: "09:00", ends_at: "12:00" },
        { starts_at: "17:00", ends_at: "20:00" }
      ]
    )

    result = described_class.call(order: order)

    expect(result.occupied_windows.size).to eq(2)
    expect(result.occupied_windows.map { |window| [ window.starts_at, window.ends_at ] }).to contain_exactly(
      [ Time.utc(2026, 6, 3, 9, 0, 0), Time.utc(2026, 6, 3, 12, 0, 0) ],
      [ Time.utc(2026, 6, 3, 17, 0, 0), Time.utc(2026, 6, 3, 20, 0, 0) ]
    )
    expect(result.occupied_windows.map { |window| window.plan.shows_per_hour }.uniq).to eq([ 3 ])
    expect(order.reload).to be_active
  end

  it "skips days with zero operating hours" do
    weekdays = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::WEEKDAY_HOURS)
    setup_order!(
      order: order,
      screen: weekdays.screens.first,
      dates: [ Date.new(2026, 6, 5), Date.new(2026, 6, 6), Date.new(2026, 6, 8) ]
    )

    result = described_class.call(order: order)

    expect(result.occupied_windows.map { |window| [ window.starts_at, window.ends_at ] }).to contain_exactly(
      [ Time.utc(2026, 6, 5, 9, 0, 0), Time.utc(2026, 6, 5, 12, 0, 0) ],
      [ Time.utc(2026, 6, 8, 9, 0, 0), Time.utc(2026, 6, 8, 12, 0, 0) ]
    )
  end

  it "keeps occupied windows when another window conflicts (AE5)" do
    setup_order!(order: order, dates: [
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
    setup_order!(order: order, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5) ])
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
    expect(result.occupied_windows.first.starts_at).to eq(Time.utc(2026, 6, 5, 9, 0, 0))
    expect(order.media_plans.active.count).to eq(2)
  end

  it "builds window claims in the organization time zone" do
    organization.update!(time_zone: "Europe/Berlin")
    setup_order!(order: order, dates: [ Date.new(2026, 3, 29) ])
    zone = Time.find_zone!("Europe/Berlin")

    result = described_class.call(order: order)

    window = result.occupied_windows.sole
    expect(window.starts_at).to eq(zone.local(2026, 3, 29, 9, 0, 0).utc)
    expect(window.ends_at).to eq(zone.local(2026, 3, 29, 12, 0, 0).utc)
    expect(window.plan.shows_per_hour).to eq(3)
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
      media_assets: [ long_clip ],
      product_name: "Triumph",
      placement_kind: :commercial,
      shows_per_hour: 3
    )
    setup_order!(order: commercial, screen: owned.screens.first, dates: [ Date.new(2026, 6, 3) ])

    result = described_class.call(order: commercial)

    expect(result.occupied_windows.size).to eq(1)
    expect(result.quota_exceeded).to be(true)
    expect(commercial.reload).to be_active
  end

  it "reports a PlacementChannel error on the line instead of raising" do
    foreign = create(:screen, owner_organization: create(:organization, :client))
    foreign.station.location.update!(operating_hours: AdvertisingNetwork::WEEKLY_HOURS)
    setup_order!(order: order, screen: foreign, dates: [ Date.new(2026, 6, 3) ])

    result = described_class.call(order: order)

    expect(result.occupied_windows).to be_empty
    expect(result.conflicted_windows.size).to eq(1)
    expect(result.conflicted_windows.first.error).to include("own/atmosphere")
    expect(order.reload).to be_draft
  end

  it "refuses activation when the clip is not broadcast-ready" do
    setup_order!(order: order, dates: [ Date.new(2026, 6, 3) ])
    asset.update_column(:processing_status, "processing")

    expect { described_class.call(order: order) }.to raise_error(
      Advertising::Error,
      I18n.t("advertising.errors.clip_not_ready")
    )
    expect(order.reload).to be_draft
    expect(MediaPlan.count).to eq(0)
  end

  context "when concurrent activates race", :concurrency do
    it "lets two order claims occupy the same screen window" do
      setup_order!(order: order, dates: [ Date.new(2026, 6, 3) ])
      other = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ asset ],
        product_name: "Other",
        shows_per_hour: 3
      )
      setup_order!(order: other, dates: [ Date.new(2026, 6, 3) ])

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
      expect(occupied.sort).to eq([ 1, 1 ])
      expect(MediaPlan.active.count).to eq(2)
      expect(AirtimeBooking.confirmed.count).to eq(2)
    end
  end
end
