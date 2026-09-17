# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommercialQuota::HourlyShowsDuration do
  let(:organization) { create(:organization, :client) }
  let(:rotation) { create(:rotation, organization: organization) }

  def add_item!(display_duration_seconds:)
    asset = create(:media_asset, :ready, :with_png_file, organization: organization)
    create(
      :rotation_item,
      rotation: rotation,
      media_asset: asset,
      display_duration_seconds: display_duration_seconds
    )
  end

  before do
    add_item!(display_duration_seconds: 10)
    add_item!(display_duration_seconds: 20)
    add_item!(display_duration_seconds: 30)
  end

  it "sums durations for all shows when shows_per_hour equals catalog size" do
    expect(described_class.call(rotation: rotation, shows_per_hour: 3)).to eq(60)
  end

  it "sums only the first M picks when shows_per_hour is less than catalog size" do
    expect(described_class.call(rotation: rotation, shows_per_hour: 2)).to eq(30)
  end

  it "wraps the catalog when shows_per_hour exceeds catalog size" do
    expect(described_class.call(rotation: rotation, shows_per_hour: 5)).to eq(90)
  end

  it "returns 0 when shows_per_hour is less than 1" do
    expect(described_class.call(rotation: rotation, shows_per_hour: 0)).to eq(0)
  end

  it "falls back to default item seconds when the catalog is empty" do
    empty_rotation = create(:rotation, organization: organization)

    expect(described_class.call(rotation: empty_rotation, shows_per_hour: 2)).to eq(30)
  end

  it "prefers item display_duration_seconds over asset duration" do
    asset = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 99)
    single = create(:rotation, organization: organization)
    create(:rotation_item, rotation: single, media_asset: asset, display_duration_seconds: 240)

    expect(described_class.call(rotation: single, shows_per_hour: 2)).to eq(480)
  end
end
