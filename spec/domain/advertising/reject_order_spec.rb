# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::RejectOrder do
  let(:organization) { create(:organization, :client) }
  let(:order) do
    Advertising::CreateOrder.call(
      organization: organization,
      created_by: create(:user, :manager, organization: organization),
      media_assets: [ create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) ],
      product_name: "Triumph"
    )
  end

  it "marks a draft rejected and stores the reason" do
    described_class.call(order: order, rejection_reason: "content_problem")

    expect(order.reload).to be_rejected
    expect(order).to be_content_problem
  end

  it "rejects an unknown reason" do
    expect { described_class.call(order: order, rejection_reason: "nope") }
      .to raise_error(Advertising::Error, I18n.t("advertising.errors.rejection_reason_invalid"))
    expect(order.reload).to be_draft
  end

  it "rejects an order that is no longer a draft" do
    order.update!(status: :active)

    expect { described_class.call(order: order, rejection_reason: "other") }
      .to raise_error(Advertising::Error, I18n.t("advertising.errors.order_not_rejectable"))
    expect(order.reload).to be_active
    expect(order.rejection_reason).to be_nil
  end
end
