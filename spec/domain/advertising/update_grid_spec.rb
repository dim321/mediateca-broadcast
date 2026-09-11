# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::UpdateGrid do
  let(:organization) { create(:organization, :client) }
  let(:order) { Advertising::CreateOrder.call(organization: organization, created_by: user, media_asset: asset, product_name: "Triumph") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:screen) do
    create(:screen, owner_organization: organization).tap do |record|
      record.station.location.update!(operating_hours: AdvertisingNetwork::WEEKLY_HOURS)
    end
  end

  def update!(lines)
    described_class.call(order: order, lines: lines)
  end

  def line_payload(screen:, days:)
    { screen_id: screen.id, days: days }
  end

  it "upserts a screen line and stores computed daily shows" do
    order.update!(shows_per_hour: 3)
    order.advertising_order_windows.create!(starts_at: "09:00", ends_at: "12:00")

    hours = Advertising::ScreenDayHours.call(
      screen: screen, date: Date.new(2026, 6, 3),
      windows: [ { start: "09:00", end: "12:00" } ],
      time_zone: "UTC"
    ).hours

    update!([ line_payload(screen: screen, days: [ { date: Date.new(2026, 6, 3), shows: 3 * hours } ]) ])

    line = order.advertising_order_lines.sole
    expect(line.screen).to eq(screen)
    expect(line.price_per_day_cents).to eq(0)
    expect(line.advertising_order_line_days.sole.shows).to eq(3 * hours)
    expect(order.reload.total_shows).to eq(3 * hours)
  end

  it "omits a zeroed day" do
    update!([ line_payload(screen: screen, days: [
      { date: Date.new(2026, 6, 3), shows: 9 },
      { date: Date.new(2026, 6, 4), shows: 9 }
    ]) ])
    update!([ line_payload(screen: screen, days: [
      { date: Date.new(2026, 6, 3), shows: 9 },
      { date: Date.new(2026, 6, 4), shows: 0 }
    ]) ])

    days = order.advertising_order_lines.sole.advertising_order_line_days
    expect(days.map(&:date)).to eq([ Date.new(2026, 6, 3) ])
  end

  it "creates a screen line with no days when every cell is zero" do
    update!([ line_payload(screen: screen, days: [ { date: Date.new(2026, 6, 3), shows: 0 } ]) ])

    line = order.advertising_order_lines.sole
    expect(line.screen).to eq(screen)
    expect(line.advertising_order_line_days).to be_empty
  end
end
