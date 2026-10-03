# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ResubmitOrder do
  let(:organization) { create(:organization, :client) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: create(:user, :manager, organization: organization),
      media_assets: [ create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) ],
      product_name: "Triumph"
    )
  end

  it "returns a rejected order to draft and clears the reason" do
    Advertising::RejectOrder.call(order: order, rejection_reason: "content_problem")

    described_class.call(order: order)

    expect(order.reload).to be_draft
    expect(order.rejection_reason).to be_nil
  end

  it "refuses an order that is not rejected" do
    expect { described_class.call(order: order) }
      .to raise_error(Advertising::Error, I18n.t("advertising.errors.order_not_resubmittable"))
    expect(order.reload).to be_draft
  end
end
