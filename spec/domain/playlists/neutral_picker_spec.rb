# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::NeutralPicker do
  let(:organization) { create(:organization, :client) }
  let(:station) { create(:station) }
  let(:for_date) { PlaylistGeneration::WEDNESDAY }
  let(:rotation) { create_clip_rotation!(organization: organization, count: 2, duration: 15) }

  def picker(strategy:, min_seconds: 10, rotation: self.rotation, station: self.station)
    described_class.new(
      rotation: rotation,
      strategy: strategy,
      station: station,
      for_date: for_date,
      min_seconds: min_seconds
    )
  end

  def create_mixed_audio_video_rotation!(organization:)
    rotation = create(:rotation, organization: organization)
    video = create(
      :media_asset, :ready, :content_validated, :with_mp4_file, :with_broadcast_ts,
      organization: organization
    )
    audio = create(:media_asset, :ready, :content_validated, :with_mp3_file, organization: organization)
    create(:rotation_item, rotation: rotation, media_asset: video, display_duration_seconds: 15)
    create(:rotation_item, rotation: rotation, media_asset: audio, display_duration_seconds: 15)
    rotation
  end

  it "rotates sequential catalog by days since epoch and wraps" do
    assets = rotation.ordered_items.map(&:media_asset)
    offset = (for_date - Date.new(1970, 1, 1)).to_i
    expected = assets.rotate(offset % assets.size)

    picks = picker(strategy: "sequential").take(3)

    expect(picks.map { |pick| pick.fetch(:media_asset) }).to eq([ expected[0], expected[1], expected[0] ])
    expect(picks.first.fetch(:duration_seconds)).to eq(15)
  end

  it "does not rotate an ordered catalog" do
    assets = rotation.ordered_items.map(&:media_asset)

    picks = picker(strategy: "ordered").take(2)

    expect(picks.map { |pick| pick.fetch(:media_asset) }).to eq(assets)
  end

  it "picks random clips from a seeded RNG without Kernel.srand" do
    srand(1)
    first = picker(strategy: "random").take(4).map { |pick| pick.fetch(:media_asset).id }
    srand(99)
    second = picker(strategy: "random").take(4).map { |pick| pick.fetch(:media_asset).id }

    expect(first).to eq(second)
    expect(first.size).to eq(4)
  end

  it "omits filler clips shorter than min_seconds and skips an empty catalog" do
    short = create_clip_rotation!(organization: organization, count: 1, duration: 5)
    mixed = create(:rotation, organization: organization)
    short_asset = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization)
    long_asset = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization)
    create(:rotation_item, rotation: mixed, media_asset: short_asset, display_duration_seconds: 5)
    create(:rotation_item, rotation: mixed, media_asset: long_asset, display_duration_seconds: 12)

    expect(picker(strategy: "ordered", rotation: short).take(1)).to eq([])
    expect(picker(strategy: "ordered", rotation: mixed).take(1).sole.fetch(:media_asset)).to eq(long_asset)
  end

  it "keeps commercial clips shorter than min_seconds when the filter is off" do
    short = create_clip_rotation!(organization: organization, count: 1, duration: 5)

    pick = picker(strategy: "ordered", min_seconds: nil, rotation: short).take(1).sole

    expect(pick.fetch(:duration_seconds)).to eq(5)
  end

  it "cycles a multi-clip catalog in order" do
    rotation = create_clip_rotation!(organization: organization, count: 3, duration: 10)
    assets = rotation.ordered_items.map(&:media_asset)
    instance = picker(strategy: "ordered", rotation: rotation)

    expect(instance.take(3).map { |pick| pick.fetch(:media_asset) }).to eq(assets)
  end

  it "skips video assets on an audio station" do
    mixed = create_mixed_audio_video_rotation!(organization: organization)
    audio_station = create(:station, :audio, location: station.location)

    kinds = picker(strategy: "ordered", rotation: mixed, station: audio_station).take(10)
      .map { |pick| pick.fetch(:media_asset).content_kind }
      .uniq

    expect(kinds).to eq([ "audio" ])
  end

  it "skips audio assets on a video station" do
    mixed = create_mixed_audio_video_rotation!(organization: organization)

    kinds = picker(strategy: "ordered", rotation: mixed).take(10)
      .map { |pick| pick.fetch(:media_asset).content_kind }
      .uniq

    expect(kinds).to eq([ "video" ])
  end

  it "continues the cursor across successive take calls" do
    rotation = create_clip_rotation!(organization: organization, count: 3, duration: 10)
    assets = rotation.ordered_items.map(&:media_asset)
    instance = picker(strategy: "ordered", rotation: rotation)

    expect(instance.take(2).map { |pick| pick.fetch(:media_asset) }).to eq(assets.first(2))
    expect(instance.take(1).sole.fetch(:media_asset)).to eq(assets[2])
  end
end
