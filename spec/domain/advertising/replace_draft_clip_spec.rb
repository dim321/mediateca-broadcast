# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ReplaceDraftClip do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:original) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  end
  let(:replacement) do
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 15).tap do |asset|
      asset.file.blob.update!(filename: "replacement.png")
    end
  end
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ original ],
      product_name: "Triumph"
    )
  end

  it "replaces the order and system rotation clip" do
    described_class.call(order: order, media_asset: replacement)

    expect(order.reload).to have_attributes(
      media_asset: replacement,
      clip_title: "replacement.png",
      duration_seconds: 15
    )
    expect(order.rotation.ordered_items.sole).to have_attributes(
      media_asset: replacement,
      display_duration_seconds: 15
    )
  end
end
