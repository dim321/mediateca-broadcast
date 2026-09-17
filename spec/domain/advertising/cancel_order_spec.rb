# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CancelOrder do
  let(:organization) { create(:organization, :client) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: create(:user, :manager, organization: organization),
      media_assets: [ create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) ],
      product_name: "Triumph",
      discount_cents: 5_000
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }
  let(:screen) { group.screens.first }

  before do
    Advertising::UpdateGrid.call(
      order: order,
      lines: [ {
        screen_id: screen.id,
        days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
      } ]
    )
    occupy_order_slot!
  end

  def occupy_order_slot!
    line = order.advertising_order_lines.sole
    zone = Time.find_zone!(organization.time_zone)
    starts_at = zone.local(2026, 6, 3)
    ends_at = zone.local(2026, 6, 4)
    plan = Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: order.rotation,
      starts_at: starts_at,
      ends_at: ends_at,
      placement_kind: order.placement_kind,
      shows_per_hour: 3
    )
    plan.update_column(:advertising_order_line_id, line.id)
    order.active!
  end

  it "soft-cancels generated slots, keeps document totals, and frees the window (AE8)" do
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
    order.rotation.ordered_items.sole.media_asset.update_column(:processing_status, "processing")

    expect { described_class.call(order: order) }.not_to raise_error
    expect(order.reload).to be_cancelled
    expect(order.media_plans.sole).to be_cancelled
  end
end
