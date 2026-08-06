# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::Cancel do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:starts_at) { Time.utc(2026, 8, 10, 10, 0, 0) }
  let(:ends_at) { Time.utc(2026, 8, 10, 10, 10, 0) }
  let(:plan) do
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  it 'soft-cancels plan and booking together (AE5)' do
    described_class.call(plan: plan)

    expect(plan.reload).to be_cancelled
    expect(plan.airtime_booking.reload).to be_cancelled
  end

  it 'frees the slot so another org can occupy the same window' do
    described_class.call(plan: plan)

    other = create(:organization, :client)
    other_group = create(:broadcast_point_group, organization: other)
    create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen: screen)
    other_rotation = create(:rotation, organization: other)

    replacement = Airtime::OccupyWithPlan.call(
      organization: other,
      broadcast_point_group: other_group,
      rotation: other_rotation,
      starts_at: starts_at,
      ends_at: ends_at
    )

    expect(replacement).to be_active
    expect(AirtimeBooking.confirmed.count).to eq(1)
  end

  it 'rejects double cancel' do
    described_class.call(plan: plan)

    expect { described_class.call(plan: plan.reload) }.to raise_error(ArgumentError, /already cancelled/)
  end

  it 'still cancels when rotation media later becomes not broadcast-ready' do
    media_asset = create(:media_asset, :ready, :with_png_file, organization: organization)
    create(:rotation_item, rotation: rotation, media_asset: media_asset)
    expect(plan).to be_persisted

    media_asset.update_column(:processing_status, 'processing')

    expect { described_class.call(plan: plan) }.not_to raise_error
    expect(plan.reload).to be_cancelled
    expect(plan.airtime_booking.reload).to be_cancelled
  end
end
