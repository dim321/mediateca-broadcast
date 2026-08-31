# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommercialQuota::CycleDuration do
  let(:organization) { create(:organization, :client) }
  let(:rotation) { create(:rotation, organization: organization) }

  it "falls back to 15s per item when durations are nil" do
    asset = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: nil)
    create(:rotation_item, rotation: rotation, media_asset: asset, display_duration_seconds: nil)

    expect(described_class.call(rotation: rotation)).to eq(15)
  end

  it "prefers item display_duration_seconds over asset duration" do
    asset = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 30)
    create(:rotation_item, rotation: rotation, media_asset: asset, display_duration_seconds: 240)

    expect(described_class.call(rotation: rotation)).to eq(240)
  end
end
