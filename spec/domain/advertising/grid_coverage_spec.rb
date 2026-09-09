# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::GridCoverage do
  let(:organization) { create(:organization, :client) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: create(:user, :manager, organization: organization),
      media_asset: create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10),
      product_name: "Triumph"
    )
  end
  let(:group) { create_group_with_hours!(organization: organization) }

  before do
    fill_order_grid!(
      order,
      screen: group.screens.first,
      dates: [
        Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 5)
      ]
    )
  end

  it "marks every grid day unoccupied before activation" do
    coverage = described_class.call(order: order)

    expect(coverage.unoccupied_days.map(&:date)).to eq([
      Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 5)
    ])
  end

  it "marks days covered by an active slot of the line as occupied" do
    result = Advertising::ActivateOrder.call(order: order)
    expect(result.occupied_windows).not_to be_empty

    coverage = described_class.call(order: order.reload)

    expect(coverage.unoccupied_days).to be_empty
    expect(coverage.days.all?(&:occupied?)).to be(true)
  end
end
