# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::Cancel do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:quota) do
    create(
      :airtime_quota,
      broadcast_point_group: group,
      seconds_total: 3_600,
      seconds_remaining: 3_000
    )
  end
  let(:booking) do
    create(
      :airtime_booking,
      organization: organization,
      broadcast_point_group: group,
      airtime_quota: quota,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 10, 0),
      seconds: 600
    )
  end

  it 'cancels and restores seconds when no media plan' do
    described_class.call(booking: booking)

    expect(booking.reload).to be_cancelled
    expect(quota.reload.seconds_remaining).to eq(3_600)
  end

  it 'rejects cancel when an active media plan is linked' do
    create(
      :media_plan,
      organization: organization,
      broadcast_point_group: group,
      airtime_booking: booking,
      starts_at: booking.starts_at,
      ends_at: booking.ends_at
    )

    expect { described_class.call(booking: booking) }.to raise_error(Airtime::CancelBlockedError)
    expect(booking.reload).to be_confirmed
    expect(quota.reload.seconds_remaining).to eq(3_000)
  end
end
