# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::OccupancyPresenter do
  let(:org) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: org) }
  let(:screen) { create(:screen) }
  let(:rotation) { create(:rotation, organization: org) }

  before { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }

  it 'returns start/end only for occupied slots' do
    plan = Airtime::OccupyWithPlan.call(
      organization: org,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 10, 0)
    )

    slots = described_class.call(broadcast_point_group: group)

    expect(slots).to eq([
      { starts_at: plan.starts_at, ends_at: plan.ends_at, occupied: true }
    ])
    expect(slots.first.keys).to match_array(%i[starts_at ends_at occupied])
  end

  it 'excludes cancelled bookings' do
    plan = Airtime::OccupyWithPlan.call(
      organization: org,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 10, 0)
    )
    Airtime::Cancel.call(plan: plan)

    expect(described_class.call(broadcast_point_group: group)).to eq([])
  end
end
