# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::ScreenTimelines do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(wiring_time, &example)
  end

  it "hashes the delivery slots a wired screen will actually show" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    asset = create(:media_asset, :ready, :with_png_file)
    cover_horizon_with_slot(station, screen, asset:)

    result = described_class.call(station:)

    expect(result.complete).to be(true)
    expect(result.digests_by_screen_id.keys).to eq([ screen.id ])
    expect(result.digests_by_screen_id[screen.id]).to eq(
      Digest::SHA256.hexdigest(JSON.generate(expected_slots(asset)))
    )
  end

  it "ignores screens that are not on the network and items without a delivery attachment" do
    station = wiring_station
    wired = wired_screen(station, ip: "192.168.33.182")
    create(:screen, station:, network_registered: false, ip_address: "192.168.33.183")
    png = create(:media_asset, :ready, :with_png_file)
    video = create(:media_asset, :ready, :with_mp4_file)
    playlists = cover_horizon_with_slot(station, wired, asset: png)
    playlists.each do |playlist|
      add_slot(playlist, wired, asset: video, offset_seconds: 30)
    end

    result = described_class.call(station:)

    expect(result.digests_by_screen_id.keys).to eq([ wired.id ])
    expect(result.digests_by_screen_id[wired.id]).to eq(
      Digest::SHA256.hexdigest(JSON.generate(expected_slots(png)))
    )
  end

  it "returns no digest for an empty timeline and reports an incomplete horizon" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    horizon_playlist(station, HORIZON_DAY)

    result = described_class.call(station:)

    expect(result.complete).to be(false)
    expect(result.digests_by_screen_id).to eq({})
    expect(screen).to be_persisted
  end

  it "uses a null starts_at when the playlist has no broadcast-day anchor" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    asset = create(:media_asset, :ready, :with_png_file)
    playlist = create(:playlist, station:, for_date: HORIZON_DAY, broadcast_day_starts_at: nil)
    create(:playlist, station:, for_date: HORIZON_DAY + 1, broadcast_day_starts_at: nil)
    add_slot(playlist, screen, asset:)

    result = described_class.call(station:)
    slots = expected_slots(asset)
    slots.first[:starts_at] = nil
    slots.slice!(1, 1)

    expect(result.digests_by_screen_id[screen.id]).to eq(Digest::SHA256.hexdigest(JSON.generate(slots)))
  end

  def expected_slots(asset)
    [ HORIZON_DAY, HORIZON_DAY + 1 ].map do |date|
      {
        for_date: date.iso8601,
        offset_seconds: 0,
        starts_at: Time.utc(date.year, date.month, date.day, 2, 0, 0).iso8601,
        duration_seconds: 10,
        media_id: asset.id
      }
    end
  end
end
