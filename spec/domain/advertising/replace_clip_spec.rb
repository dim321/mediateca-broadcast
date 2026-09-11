# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ReplaceClip do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:original) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: original,
      product_name: "Triumph"
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }
  let(:replacement) { clip_named("triumph-v2.png", duration: 15) }

  def clip_named(filename, duration:, **attrs)
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: duration, **attrs).tap do |asset|
      asset.file.blob.update!(filename: filename)
    end
  end

  def activate!
    fill_order_grid!(order, screen: group.screens.first, dates: [ Date.new(2026, 6, 3) ])
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  it "enqueues GenerateForDateJob for active media plans of the order rotation (AE7)" do
    travel_to Time.utc(2026, 9, 2, 12, 0, 0) do
      fill_order_grid!(order, screen: group.screens.first, dates: [ Date.new(2026, 9, 3) ])
      Advertising::ActivateOrder.call(order: order)
      order.reload
      station_id = group.screens.first.station_id

      expect {
        described_class.call(order: order, media_asset: replacement)
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station_id, "2026-09-03")
    end
  end

  it "swaps the system rotation item, snapshots the clip, and keeps slot ids (AE7)" do
    activate!
    plan_ids = order.media_plans.order(:id).pluck(:id)
    booking_ids = order.media_plans.map(&:airtime_booking_id)

    described_class.call(order: order, media_asset: replacement)

    order.reload
    expect(order).to have_attributes(
      document_version: 2,
      media_asset: replacement,
      clip_title: "triumph-v2.png",
      duration_seconds: 15
    )
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ replacement ])
    expect(order.rotation.ordered_items.sole.display_duration_seconds).to eq(15)
    expect(order.media_plans.order(:id).pluck(:id)).to eq(plan_ids)
    expect(order.media_plans.map(&:airtime_booking_id)).to eq(booking_ids)
  end

  it "rejects a clip that is not broadcast-ready" do
    activate!
    pending_clip = create(
      :media_asset,
      :with_png_file,
      organization: organization,
      duration_seconds: 15,
      processing_status: "processing"
    )

    expect do
      described_class.call(order: order, media_asset: pending_clip)
    end.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_not_ready"))

    expect(order.reload.document_version).to eq(1)
    expect(order.media_asset).to eq(original)
  end

  it "rejects a ready video that has no broadcast file" do
    activate!
    video = create(:media_asset, :ready, :with_mp4_file, organization: organization, duration_seconds: 8)

    expect do
      described_class.call(order: order, media_asset: video)
    end.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_not_ready"))
  end

  it "rejects replacement on a draft order" do
    expect do
      described_class.call(order: order, media_asset: replacement)
    end.to raise_error(Advertising::Error, I18n.t("advertising.errors.order_not_active"))

    expect(order.reload.document_version).to eq(1)
  end

  it "does not recreate occupancy" do
    activate!

    expect do
      described_class.call(order: order, media_asset: replacement)
    end.not_to change(AirtimeBooking, :count)
  end
end
