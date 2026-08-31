# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::UpdateGrid do
  let(:organization) { create(:organization, :client) }
  let(:order) { Advertising::CreateOrder.call(organization: organization, created_by: user, media_asset: asset, product_name: "Triumph") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def update!(lines)
    described_class.call(order: order, lines: lines)
  end

  def line_payload(group:, price: 34_020_00, days:)
    { broadcast_point_group_id: group.id, price_per_day_cents: price, days: days }
  end

  it "upserts lines and days then recalculates totals" do
    dates = (Date.new(2026, 6, 3)..Date.new(2026, 6, 5)).map { |date| { date: date, shows: 36 } }

    update!([ line_payload(group: group, days: dates) ])

    line = order.advertising_order_lines.sole
    expect(line.broadcast_point_group).to eq(group)
    expect(line.advertising_order_line_days.count).to eq(3)
    expect(line.total_shows).to eq(108)
    expect(line.total_sum_cents).to eq(3 * 34_020_00)
    expect(order.reload.total_shows).to eq(108)
    expect(order.total_sum_cents).to eq(3 * 34_020_00)
  end

  it "replaces days not present in the payload (a dash removes the cell)" do
    update!([ line_payload(group: group, days: [
      { date: Date.new(2026, 6, 3), shows: 36 },
      { date: Date.new(2026, 6, 4), shows: 36 }
    ]) ])
    update!([ line_payload(group: group, days: [
      { date: Date.new(2026, 6, 4), shows: 24 }
    ]) ])

    days = order.advertising_order_lines.sole.advertising_order_line_days
    expect(days.map(&:date)).to eq([ Date.new(2026, 6, 4) ])
    expect(days.sole.shows).to eq(24)
  end

  it "rejects a line whose group has no operating hours (AE3)" do
    bare = create(:broadcast_point_group, organization: organization)
    screen = create(:screen, owner_organization: organization)
    create(:broadcast_point_group_membership, broadcast_point_group: bare, screen: screen)

    expect do
      update!([ line_payload(group: bare, days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]) ])
    end.to raise_error(Advertising::InvalidGrid) { |error|
      expect(error.order.advertising_order_lines.first.errors[:broadcast_point_group]).to be_present
    }
    expect(order.reload.advertising_order_lines).to be_empty
  end

  it "rejects shows that are not a multiple of the group's min hours and suggests neighbours (AE2)" do
    eleven = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::ELEVEN_HOURS)

    expect do
      update!([ line_payload(group: eleven, days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]) ])
    end.to raise_error(Advertising::InvalidGrid) { |error|
      day = error.order.advertising_order_lines.first.advertising_order_line_days.first
      expect(day.errors[:shows]).to be_present
      expect(day.errors.details[:shows].first).to include(lower: 33, upper: 44)
    }
    expect(AdvertisingOrderLineDay.count).to eq(0)
  end

  it "accepts 44 shows against 11 operating hours" do
    eleven = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::ELEVEN_HOURS)

    update!([ line_payload(group: eleven, days: [ { date: Date.new(2026, 6, 3), shows: 44 } ]) ])

    expect(order.advertising_order_lines.sole.advertising_order_line_days.sole.shows).to eq(44)
  end

  it "rejects a day with zero operating hours" do
    weekdays = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::WEEKDAY_HOURS)
    saturday = Date.new(2026, 6, 6)

    expect do
      update!([ line_payload(group: weekdays, days: [ { date: saturday, shows: 36 } ]) ])
    end.to raise_error(Advertising::InvalidGrid)
  end
end
