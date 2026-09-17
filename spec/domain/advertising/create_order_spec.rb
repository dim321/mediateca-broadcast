# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CreateOrder do
  let(:organization) { create(:organization, :client, :with_profile, profile_business_sphere: sphere) }
  let(:sphere) { create(:directory_business_sphere, name: "Retail") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:media_asset) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  end

  def create_order!(media_assets: [ media_asset ], **attrs)
    described_class.call(
      organization: organization,
      created_by: user,
      media_assets: media_assets,
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

  it "builds a system-managed rotation from media assets without a legacy FK" do
    order = create_order!

    expect(order.media_asset_id).to be_nil
    expect(order.rotation).to be_system_managed
    expect(order.rotation.organization).to eq(organization)
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ media_asset ])
  end

  it "creates ordered rotation items for each media asset" do
    a = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
    b = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12)
    c = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 14)

    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ a, b, c ],
      product_name: "Multi",
      shows_per_hour: 3
    )

    expect(order.media_asset_id).to be_nil
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ a, b, c ])
    expect(order.rotation.ordered_items.map(&:display_duration_seconds)).to eq([ 10, 12, 14 ])
  end

  it "rejects an empty media_assets list" do
    expect {
      Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [], product_name: "X"
      )
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clips_required"))
  end

  it "rejects duplicate media assets" do
    expect {
      create_order!(media_assets: [ media_asset, media_asset ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clips_duplicate"))
  end

  it "rejects a clip from another organization" do
    foreign = create(:media_asset, :ready, :with_png_file, duration_seconds: 10)

    expect {
      create_order!(media_assets: [ foreign ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_foreign"))
  end

  it "rejects a clip that is not broadcast-ready" do
    pending_clip = create(
      :media_asset,
      :with_png_file,
      organization: organization,
      duration_seconds: 10,
      processing_status: "processing"
    )

    expect {
      create_order!(media_assets: [ pending_clip ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.clip_not_ready"))
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

  it "stores shows_per_hour on the draft" do
    order = create_order!(shows_per_hour: 3)

    expect(order.shows_per_hour).to eq(3)
  end

  it "stores the distribution strategy on the draft" do
    order = create_order!(distribution_strategy: :chess)

    expect(order).to be_chess
  end
end
