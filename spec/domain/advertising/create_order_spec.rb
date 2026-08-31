# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CreateOrder do
  let(:organization) { create(:organization, :client, :with_profile, profile_business_sphere: sphere) }
  let(:sphere) { create(:directory_business_sphere, name: "Retail") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:media_asset) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  end

  def create_order!(**attrs)
    described_class.call(
      organization: organization,
      created_by: user,
      media_asset: media_asset,
      product_name: "Triumph",
      **attrs
    )
  end

  it "creates a draft owned by the organization and author" do
    order = create_order!

    expect(order).to be_persisted
    expect(order).to be_draft
    expect(order.organization).to eq(organization)
    expect(order.created_by).to eq(user)
    expect(order.business_sphere).to eq("Retail")
  end

  it "snapshots the clip and builds a system-managed singleton rotation" do
    order = create_order!

    expect(order.duration_seconds).to eq(10)
    expect(order.clip_title).to be_present
    expect(order.rotation).to be_system_managed
    expect(order.rotation.organization).to eq(organization)
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ media_asset ])
  end

  it "names the system rotation after the order number" do
    order = create_order!

    expect(order.rotation.name).to eq(I18n.t("advertising.system_rotation_name", number: order.id))
  end

  it "accepts commercial placement, coefficient and discount" do
    order = create_order!(
      placement_kind: :commercial,
      coefficient_percent: -10,
      discount_cents: 1_000
    )

    expect(order).to be_commercial
    expect(order.coefficient_percent).to eq(-10)
    expect(order.discount_cents).to eq(1_000)
    expect(order.total_shows).to eq(0)
    expect(order.total_sum_cents).to eq(0)
  end

  it "does not occupy airtime" do
    expect { create_order! }.not_to change(MediaPlan, :count)
  end
end
