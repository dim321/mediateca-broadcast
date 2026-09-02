# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::ResolvePlayEvent do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.utc(2026, 9, 2, 12, 0, 0), &example)
  end

  def station_setup
    location = create(:location, time_zone: "UTC")
    station = create(:station, location: location, offline_cache_hours: 24)
    screen = create(:screen, station: station)
    [ station, screen ]
  end

  def create_current_item(station, screen, asset:, source_kind:, media_plan: nil)
    playlist = create(
      :playlist,
      station: station,
      for_date: Date.new(2026, 9, 2),
      generated_at: Time.current,
      broadcast_day_starts_at: Time.utc(2026, 9, 2, 9, 0, 0)
    )
    create(
      :playlist_item,
      playlist: playlist,
      media_asset: asset,
      source_kind: source_kind,
      media_plan: media_plan,
      position: 1
    ).tap do |item|
      item.screens = [ screen ]
      item.save!
    end
  end

  it "attributes filler play to the operator organization (AE12)" do
    operator = create(:organization, :operator)
    station, screen = station_setup
    asset = create(:media_asset, :ready, :with_png_file, organization: operator)
    create_current_item(station, screen, asset: asset, source_kind: "filler")

    result = described_class.call(station: station, screen: screen, media_asset_id: asset.id)

    expect(result.organization).to eq(operator)
    expect(result.media_asset).to eq(asset)
  end

  it "attributes a live commercial item to the plan organization (AE12)" do
    create(:organization, :operator)
    client = create(:organization, :client)
    station, screen = station_setup
    asset = create(:media_asset, :ready, :with_png_file, organization: client)
    plan = create(:media_plan, organization: client, status: :active)
    create_current_item(station, screen, asset: asset, source_kind: "media_plan", media_plan: plan)

    result = described_class.call(station: station, screen: screen, media_asset_id: asset.id)

    expect(result.organization).to eq(client)
  end

  it "attributes a commercial item whose plan is no longer active to the operator" do
    operator = create(:organization, :operator)
    client = create(:organization, :client)
    station, screen = station_setup
    asset = create(:media_asset, :ready, :with_png_file, organization: client)
    plan = create(:media_plan, organization: client)
    plan.update_columns(status: MediaPlan.statuses.fetch("cancelled"))
    create_current_item(station, screen, asset: asset, source_kind: "media_plan", media_plan: plan)

    result = described_class.call(station: station, screen: screen, media_asset_id: asset.id)

    expect(result.organization).to eq(operator)
  end

  it "returns nil when a current playlist exists but the asset is not on that screen (AE12)" do
    create(:organization, :operator)
    station, screen = station_setup
    listed = create(:media_asset, :ready, :with_png_file)
    other = create(:media_asset, :ready, :with_png_file)
    create_current_item(station, screen, asset: listed, source_kind: "filler")

    expect(described_class.call(station: station, screen: screen, media_asset_id: other.id)).to be_nil
  end

  it "falls back to an overlapping media plan when the station has no current playlist in the horizon" do
    client = create(:organization, :client)
    station, screen = station_setup
    asset = create(:media_asset, :ready, :with_png_file, organization: client)
    rotation = create(:rotation, organization: client)
    create(:rotation_item, rotation: rotation, media_asset: asset, position: 1)
    group = create(:broadcast_point_group, organization: client)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    create(
      :media_plan,
      organization: client,
      rotation: rotation,
      broadcast_point_group: group,
      starts_at: 1.hour.ago,
      ends_at: 2.hours.from_now
    )

    result = described_class.call(station: station, screen: screen, media_asset_id: asset.id)

    expect(result.organization).to eq(client)
    expect(result.media_asset).to eq(asset)
  end
end
