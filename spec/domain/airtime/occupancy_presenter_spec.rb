# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::OccupancyPresenter do
  it 'returns start/end only for occupied slots' do
    org = create(:organization, :client)
    group = create(:broadcast_point_group, organization: org)
    screen = create(:screen)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    quota = create(:airtime_quota, broadcast_point_group: group)
    booking = Airtime::Book.call(
      quota: quota,
      organization: org,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 10, 0)
    )

    slots = described_class.call(broadcast_point_group: group)

    expect(slots).to eq([
      { starts_at: booking.starts_at, ends_at: booking.ends_at, occupied: true }
    ])
    expect(slots.first.keys).to match_array(%i[starts_at ends_at occupied])
  end
end
