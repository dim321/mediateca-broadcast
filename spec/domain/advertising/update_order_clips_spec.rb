# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::UpdateOrderClips do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:clip_a) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10).tap do |asset|
      asset.file.blob.update!(filename: "clip-a.png")
    end
  end
  let(:clip_b) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12).tap do |asset|
      asset.file.blob.update!(filename: "clip-b.png")
    end
  end
  let(:clip_c) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 14).tap do |asset|
      asset.file.blob.update!(filename: "clip-c.png")
    end
  end
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ clip_a ],
      product_name: "Triumph"
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }

  def activate!
    fill_order_grid!(order, screen: group.screens.first, dates: [ Date.new(2026, 6, 3) ])
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  it "syncs ordered rotation items on a draft order without enqueueing regen" do
    expect {
      described_class.call(order: order, media_assets: [ clip_b, clip_c ])
    }.not_to have_enqueued_job(Playlists::GenerateForDateJob)

    order.reload
    expect(order.media_asset_id).to be_nil
    expect(order.document_version).to eq(1)
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ clip_b, clip_c ])
    expect(order.rotation.ordered_items.map(&:display_duration_seconds)).to eq([ 12, 14 ])
  end

  it "syncs clips on an active order, bumps document_version, and enqueues regen" do
    travel_to Time.utc(2026, 9, 2, 12, 0, 0) do
      fill_order_grid!(order, screen: group.screens.first, dates: [ Date.new(2026, 9, 3) ])
      Advertising::ActivateOrder.call(order: order)
      order.reload
      station_id = group.screens.first.station_id
      plan_ids = order.media_plans.order(:id).pluck(:id)
      booking_ids = order.media_plans.map(&:airtime_booking_id)

      expect {
        described_class.call(order: order, media_assets: [ clip_b, clip_c ])
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station_id, "2026-09-03")

      order.reload
      expect(order.media_asset_id).to be_nil
      expect(order.document_version).to eq(2)
      expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ clip_b, clip_c ])
      expect(order.media_plans.order(:id).pluck(:id)).to eq(plan_ids)
      expect(order.media_plans.map(&:airtime_booking_id)).to eq(booking_ids)
    end
  end

  it "does not recreate occupancy on an active order" do
    activate!

    expect {
      described_class.call(order: order, media_assets: [ clip_b ])
    }.not_to change(AirtimeBooking, :count)
  end

  it "rejects an empty media_assets list" do
    expect {
      described_class.call(order: order, media_assets: [])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clips_required"))

    expect(order.reload.rotation.ordered_items.map(&:media_asset)).to eq([ clip_a ])
  end

  it "rejects duplicate media assets" do
    expect {
      described_class.call(order: order, media_assets: [ clip_a, clip_a ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clips_duplicate"))
  end

  it "rejects a clip from another organization" do
    foreign = create(:media_asset, :ready, :with_png_file, duration_seconds: 10)

    expect {
      described_class.call(order: order, media_assets: [ foreign ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_foreign"))
  end

  it "rejects a clip that is not broadcast-ready" do
    pending_clip = create(
      :media_asset,
      :with_png_file,
      organization: organization,
      duration_seconds: 15,
      processing_status: "processing"
    )

    expect {
      described_class.call(order: order, media_assets: [ pending_clip ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_not_ready"))

    expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(clip_a)
  end

  it "rejects a ready video that has no broadcast file" do
    video = create(:media_asset, :ready, :with_mp4_file, organization: organization, duration_seconds: 8)

    expect {
      described_class.call(order: order, media_assets: [ video ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_not_ready"))
  end

  it "rejects updates on non-editable order statuses" do
    activate!
    order.update!(status: :completed)

    expect {
      described_class.call(order: order, media_assets: [ clip_b ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.order_clips_not_editable"))
  end
end
