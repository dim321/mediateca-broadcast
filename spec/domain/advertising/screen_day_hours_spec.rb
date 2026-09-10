# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ScreenDayHours do
  let(:zone) { "UTC" }
  let(:date) { Date.new(2026, 6, 3) } # Wednesday
  let(:hours_hash) { AdvertisingNetwork::WEEKLY_HOURS }
  let(:screen) { create(:screen) }

  before { screen.station.location.update!(operating_hours: hours_hash, time_zone: zone) }

  def result(windows)
    described_class.call(screen: screen.reload, date: date, windows: windows, time_zone: zone)
  end

  it "counts hours where order windows intersect the screen schedule" do
    out = result([ { start: "09:00", end: "12:00" } ])
    expect(out.hours).to eq(3)
    expect(out.ranges.size).to eq(1)
    expect(out.ranges.first[0].strftime("%H:%M")).to eq("09:00")
    expect(out.ranges.first[1].strftime("%H:%M")).to eq("12:00")
  end

  it "clips a window to the screen's open interval" do
    # WEEKLY_HOURS is 09:00–21:00 every day
    out = result([ { start: "07:00", end: "10:00" } ])
    expect(out.hours).to eq(1)
    expect(out.ranges.first[0].strftime("%H:%M")).to eq("09:00")
    expect(out.ranges.first[1].strftime("%H:%M")).to eq("10:00")
  end

  it "returns zero when the screen is closed that weekday" do
    closed = AdvertisingNetwork::WEEKLY_HOURS.merge("wed" => [])
    screen.update!(inherit_operating_hours_from_location: false, operating_hours: closed)
    out = result([ { start: "09:00", end: "12:00" } ])
    expect(out.hours).to eq(0)
    expect(out.ranges).to eq([])
  end

  it "counts hours from several windows without double-counting overlap" do
    out = result([
      { start: "09:00", end: "12:00" },
      { start: "16:00", end: "21:00" }
    ])
    expect(out.hours).to eq(8)
  end

  describe ".open_clock_hours" do
    it "lists every clock hour the screen is open that day" do
      hours = described_class.open_clock_hours(screen: screen.reload, date: date, time_zone: zone)
      expect(hours).to eq((9..20).to_a)
    end
  end
end
