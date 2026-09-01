# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::RecalculateTotals do
  let(:order) { create(:advertising_order, discount_cents: 10_000) }
  let(:group_a) { create(:broadcast_point_group, organization: order.organization) }
  let(:group_b) { create(:broadcast_point_group, organization: order.organization) }

  it "sets line and order totals as days × price minus discount (AE1)" do
    line_a = create(:advertising_order_line, advertising_order: order, broadcast_point_group: group_a,
      price_per_day_cents: 34_020_00)
    line_b = create(:advertising_order_line, advertising_order: order, broadcast_point_group: group_b,
      price_per_day_cents: 20_000_00)
    create_order_line_days!(line_a, dates: Date.new(2026, 6, 3)..Date.new(2026, 6, 5), shows: 36)
    create_order_line_days!(line_b, dates: Date.new(2026, 6, 3)..Date.new(2026, 6, 4), shows: 12)

    described_class.call(order: order)

    expect(line_a.reload.total_shows).to eq(108)
    expect(line_a.total_sum_cents).to eq(3 * 34_020_00)
    expect(line_b.reload.total_shows).to eq(24)
    expect(line_b.total_sum_cents).to eq(2 * 20_000_00)
    expect(order.reload.total_shows).to eq(132)
    expect(order.total_sum_cents).to eq((3 * 34_020_00) + (2 * 20_000_00) - 10_000)
  end

  it "treats coefficient as informational and does not scale the sum" do
    order.update!(coefficient_percent: 50, discount_cents: 0)
    line = create(:advertising_order_line, advertising_order: order, price_per_day_cents: 1_000)
    create(:advertising_order_line_day, advertising_order_line: line, date: Date.new(2026, 6, 3), shows: 12)

    described_class.call(order: order)

    expect(order.reload.total_sum_cents).to eq(1_000)
  end

  it "clamps the order total at zero when discount exceeds line sums" do
    order.update!(discount_cents: 50_000)
    line = create(:advertising_order_line, advertising_order: order, price_per_day_cents: 1_000)
    create(:advertising_order_line_day, advertising_order_line: line, date: Date.new(2026, 6, 3), shows: 12)

    described_class.call(order: order)

    expect(order.reload.total_sum_cents).to eq(0)
  end
end
