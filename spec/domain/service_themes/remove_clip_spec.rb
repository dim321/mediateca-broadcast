# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::RemoveClip do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:organization, :operator) }
  let(:user) { create(:user, :traffic_manager, organization: operator) }
  let(:theme) { ServiceThemes::Create.call(organization: operator, name: "Салон красоты") }
  let(:asset) do
    create(:media_asset, :ready, :with_png_file, :content_validated,
      organization: operator, content_type: "service", visibility: "network", uploaded_by: user)
  end
  let(:item) { theme.welcome_rotation.rotation_items.create!(media_asset: asset) }

  it "removes the clip from the folder and keeps the media asset" do
    item

    expect {
      described_class.call(theme: theme, rotation_item: item)
    }.to change(RotationItem, :count).by(-1)
      .and not_change(MediaAsset, :count)

    expect(MediaAsset.find_by(id: asset.id)).to eq(asset)
    expect(theme.welcome_rotation.rotation_items.find_by(media_asset: asset)).to be_nil
  end

  it "regenerates playlists after the clip leaves the folder" do
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, rotation: theme.welcome_rotation)
    item

    travel_to(Time.utc(2026, 9, 28, 12, 0, 0)) do
      expect {
        described_class.call(theme: theme, rotation_item: item)
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-28")
    end
  end

  it "rejects a clip that belongs to another theme" do
    other = ServiceThemes::Create.call(organization: operator, name: "Рыбный отдел")
    foreign = other.welcome_rotation.rotation_items.create!(media_asset: asset)

    expect {
      described_class.call(theme: theme, rotation_item: foreign)
    }.to raise_error(ArgumentError)
      .and not_change(RotationItem, :count)
  end
end
