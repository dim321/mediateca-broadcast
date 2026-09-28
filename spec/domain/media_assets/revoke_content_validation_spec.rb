# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssets::RevokeContentValidation do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:sphere) { create(:directory_business_sphere, name: "Retail") }
  let(:organization) { create(:organization, :client, :with_profile, profile_business_sphere: sphere, time_zone: "UTC") }
  let(:user) { create(:user, :traffic_manager, organization: organization) }
  let(:asset) do
    create(:media_asset, :ready, :with_png_file, :content_validated, organization: organization, duration_seconds: 10)
  end

  it "does nothing when the asset is unmarked" do
    unmarked = create(:media_asset, :ready, :with_png_file, organization: organization)

    expect {
      described_class.call(media_asset: unmarked)
    }.not_to change(AdvertisingOrder, :count)
    expect(unmarked.reload.content_validated?).to be false
  end

  it "cancels an active order and keeps the draft order rotation item" do
    draft = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Draft",
      shows_per_hour: 3
    )
    active = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Live",
      shows_per_hour: 3
    )
    group = create_group_with_hours!(organization: organization)
    fill_order_grid!(active, screen: group.screens.first, dates: [ Date.new(2026, 6, 3) ])
    Advertising::ActivateOrder.call(order: active)

    described_class.call(media_asset: asset)

    expect(active.reload).to be_cancelled
    expect(draft.reload).to be_draft
    expect(draft.rotation.rotation_items.where(media_asset: asset)).to exist
    expect(active.rotation.rotation_items.where(media_asset: asset)).to exist
    expect(asset.reload.content_validated?).to be false
  end

  it "removes a service-theme item and enqueues regen for that rotation" do
    operator = create(:organization, :operator)
    theme = ServiceThemes::Create.call(organization: operator, name: "Theme")
    service_asset = create(
      :media_asset, :ready, :with_png_file, :content_validated,
      organization: operator, content_type: "service", visibility: "network"
    )
    theme.welcome_rotation.rotation_items.create!(
      media_asset: service_asset,
      display_duration_seconds: service_asset.duration_seconds
    )
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, rotation: theme.welcome_rotation)

    travel_to(Time.utc(2026, 9, 28, 12, 0, 0)) do
      expect {
        described_class.call(media_asset: service_asset)
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-28")
    end

    expect(theme.welcome_rotation.rotation_items.where(media_asset: service_asset)).to be_empty
    expect(service_asset.reload.content_validated?).to be false
  end
end
