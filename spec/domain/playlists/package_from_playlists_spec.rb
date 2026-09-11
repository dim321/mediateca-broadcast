# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::PackageFromPlaylists do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.utc(2026, 9, 2, 18, 0, 0), &example)
  end

  def station_with_screen(cache_hours: 24)
    location = create(:location, time_zone: "UTC")
    station = create(:station, location: location, offline_cache_hours: cache_hours)
    screen = create(:screen, station: station)
    [ station, screen ]
  end

  def create_day_playlist(station, screen, for_date:, offset_seconds:, asset:, source_kind: "filler", media_plan: nil)
    anchor = Time.utc(for_date.year, for_date.month, for_date.day, 2, 0, 0)
    playlist = create(
      :playlist,
      station: station,
      for_date: for_date,
      broadcast_day_starts_at: anchor,
      generated_at: Time.current
    )
    create(
      :playlist_item,
      playlist: playlist,
      media_asset: asset,
      position: 1,
      offset_seconds: offset_seconds,
      duration_seconds: 10,
      source_kind: source_kind,
      media_plan: media_plan
    ).tap do |item|
      item.screens = [ screen ]
      item.save!
    end
    playlist
  end

  it "stitches current playlists whose days overlap the offline cache horizon (AE9)" do
    station, screen = station_with_screen
    today_asset = create(:media_asset, :ready, :with_png_file)
    tomorrow_asset = create(:media_asset, :ready, :with_png_file)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), offset_seconds: 0, asset: today_asset)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), offset_seconds: 0, asset: tomorrow_asset)

    package = described_class.call(station: station)

    expect(package[:entries].map { |entry| entry[:media][:id] }).to eq([ today_asset.id, tomorrow_asset.id ])
    expect(package[:entries].map { |entry| entry[:for_date] }).to eq([ "2026-09-02", "2026-09-03" ])
    expect(package[:screen_map]).to eq(screen.id.to_s => [ 0, 1 ])
    expect(package[:etag]).to eq(package[:version])
    expect(package).not_to have_key(:items)
  end

  it "returns empty entries without generating when no current playlist exists (AE10)" do
    station, = station_with_screen
    allow(Playlists::GenerateForDate).to receive(:call)

    package = described_class.call(station: station)

    expect(package[:entries]).to eq([])
    expect(package[:screen_map]).to eq({})
    expect(Playlists::GenerateForDate).not_to have_received(:call)
  end

  it "enqueues generate for missing horizon dates and not for dates that already have a current playlist" do
    station, screen = station_with_screen
    asset = create(:media_asset, :ready, :with_png_file)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), offset_seconds: 0, asset: asset)

    expect { described_class.call(station: station) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).exactly(:once).with(station.id, "2026-09-03")
  end

  it "does not enqueue when every horizon date already has a current playlist" do
    station, screen = station_with_screen
    asset = create(:media_asset, :ready, :with_png_file)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), offset_seconds: 0, asset: asset)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), offset_seconds: 0, asset: asset)

    expect { described_class.call(station: station) }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
  end

  it "keeps etag stable when generated_at is not part of the manifest" do
    station, screen = station_with_screen
    asset = create(:media_asset, :ready, :with_png_file)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), offset_seconds: 0, asset: asset)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), offset_seconds: 0, asset: asset)

    first = described_class.call(station: station, now: Time.utc(2026, 9, 2, 18, 0, 0))
    second = described_class.call(station: station, now: Time.utc(2026, 9, 2, 18, 5, 0))

    expect(first[:etag]).to eq(second[:etag])
    expect(first[:generated_at]).not_to eq(second[:generated_at])
  end

  it "computes starts_at from the broadcast-day anchor plus offset" do
    station, screen = station_with_screen
    asset = create(:media_asset, :ready, :with_png_file)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), offset_seconds: 90, asset: asset)
    create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), offset_seconds: 0, asset: asset)

    package = described_class.call(station: station)
    today = package[:entries].find { |entry| entry[:for_date] == "2026-09-02" }

    expect(today[:broadcast_day_starts_at]).to eq("2026-09-02T02:00:00Z")
    expect(today[:starts_at]).to eq("2026-09-02T02:01:30Z")
    expect(today[:offset_seconds]).to eq(90)
    expect(today[:source_kind]).to eq("filler")
    expect(today[:media_plan_id]).to be_nil
  end
end
