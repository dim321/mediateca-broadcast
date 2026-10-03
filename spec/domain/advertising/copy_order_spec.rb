# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CopyOrder do
  let(:organization) { create(:organization, :client, :with_profile, profile_business_sphere: sphere) }
  let(:sphere) { create(:directory_business_sphere, name: "Retail") }
  let(:author) { create(:user, :manager, organization: organization) }
  let(:copier) { create(:user, :administrator, organization: organization) }
  let(:first_asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:second_asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def screen
    group.screens.first.tap do |record|
      next if record.broadcast_portrait.present?

      create(:broadcast_portrait, :for_screen, screen: record, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    end
  end

  def source_order
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: author,
      media_assets: [ first_asset, second_asset ],
      product_name: "Triumph",
      placement_kind: :commercial,
      shows_per_hour: 4,
      distribution_strategy: :odd_days,
      coefficient_percent: -10,
      discount_cents: 2_000
    )
    fill_order_grid!(
      order,
      screen: screen,
      dates: [ Date.new(2026, 6, 3) ],
      shows_per_hour: 4,
      windows: [ { starts_at: "08:00", ends_at: "12:00" } ]
    )
    order.advertising_order_windows.create!(starts_at: "14:00", ends_at: "18:00")
    order.update!(
      distribution_strategy: :odd_days,
      clip_title: "spot.mp4",
      duration_seconds: 10,
      document_version: 4,
      status: :active
    )
    order.reload
  end

  it "copies the order attributes and leaves the source dates behind" do
    source = source_order

    copy = described_class.call(source: source, created_by: copier)

    expect(copy).to be_persisted.and be_draft.and have_attributes(
      organization: organization,
      created_by: copier,
      business_sphere: "Retail",
      product_name: "Triumph",
      placement_kind: "commercial",
      shows_per_hour: 4,
      distribution_strategy: "odd_days",
      coefficient_percent: -10,
      discount_cents: 2_000,
      clip_title: "spot.mp4",
      duration_seconds: 10,
      document_version: 1,
      rejection_reason: nil,
      total_shows: 0
    )
    expect(copy.rotation_id).not_to eq(source.rotation_id)
    expect(copy.rotation.ordered_items.map(&:media_asset)).to eq([ first_asset, second_asset ])
    windows = copy.advertising_order_windows.map do |window|
      [ window.starts_at.strftime("%H:%M"), window.ends_at.strftime("%H:%M") ]
    end
    expect(windows).to eq([ [ "08:00", "12:00" ], [ "14:00", "18:00" ] ])
    expect(copy.advertising_order_lines.map { |line| [ line.screen, line.advertising_order_line_days.to_a ] })
      .to eq([ [ screen, [] ] ])
    source.reload
    expect([ source.status, source.advertising_order_line_days.map(&:date) ]).to eq([ "active", [ Date.new(2026, 6, 3) ] ])
  end
end
