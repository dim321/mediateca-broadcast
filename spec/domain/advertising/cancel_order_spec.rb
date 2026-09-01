# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CancelOrder do
  let(:organization) { create(:organization, :client) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: create(:user, :manager, organization: organization),
      media_asset: create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10),
      product_name: "Triumph",
      discount_cents: 5_000
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }

  before do
    Advertising::UpdateGrid.call(
      order: order,
      lines: [ {
        broadcast_point_group_id: group.id,
        price_per_day_cents: 34_020_00,
        days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
      } ]
    )
  end

  it "soft-cancels generated slots, keeps document totals, and frees the window (AE8)" do
    Advertising::ActivateOrder.call(order: order)
    totals = order.reload.attributes.slice("total_shows", "total_sum_cents")
    plan = order.media_plans.sole
    window = [ plan.starts_at, plan.ends_at ]

    described_class.call(order: order)

    expect(order.reload).to be_cancelled
    expect(plan.reload).to be_cancelled
    expect(plan.airtime_booking.reload).to be_cancelled
    expect(order.attributes.slice("total_shows", "total_sum_cents")).to eq(totals)

    replacement = Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: create(:rotation, organization: organization),
      starts_at: window[0],
      ends_at: window[1]
    )
    expect(replacement).to be_active
  end

  it "cancels remaining active slots even if the rotation is no longer broadcast-ready" do
    Advertising::ActivateOrder.call(order: order)
    order.media_asset.update_column(:processing_status, "processing")

    expect { described_class.call(order: order) }.not_to raise_error
    expect(order.reload).to be_cancelled
    expect(order.media_plans.sole).to be_cancelled
  end
end
