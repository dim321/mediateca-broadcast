# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::Reschedule do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:plan) do
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 10, 0)
    )
  end

  it 'moves booking and plan windows together' do
    described_class.call(
      plan: plan,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 5, 0)
    )

    plan.reload
    booking = plan.airtime_booking
    expect(plan.starts_at).to eq(Time.utc(2026, 8, 10, 12, 0, 0))
    expect(plan.ends_at).to eq(Time.utc(2026, 8, 10, 12, 5, 0))
    expect(booking.starts_at).to eq(plan.starts_at)
    expect(booking.ends_at).to eq(plan.ends_at)
    expect(booking.seconds).to eq(300)
    expect(plan.rotation_id).to eq(rotation.id)
  end

  it 'keeps original plan when target slot is busy (AE3)' do
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 10, 0)
    )
    original_starts = plan.starts_at
    original_ends = plan.ends_at

    expect do
      described_class.call(
        plan: plan,
        broadcast_point_group: group,
        starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 10, 0)
      )
    end.to raise_error(Airtime::ConflictError)

    plan.reload
    expect(plan.starts_at).to eq(original_starts)
    expect(plan.ends_at).to eq(original_ends)
    expect(plan.airtime_booking.starts_at).to eq(original_starts)
  end

  it 'can move to a free target window' do
    described_class.call(
      plan: plan,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 14, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 14, 20, 0)
    )

    expect(plan.reload.starts_at).to eq(Time.utc(2026, 8, 10, 14, 0, 0))
    expect(plan.airtime_booking.reload.ends_at).to eq(Time.utc(2026, 8, 10, 14, 20, 0))
  end
end
