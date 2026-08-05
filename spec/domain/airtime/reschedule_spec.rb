# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::Reschedule do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:quota) do
    create(
      :airtime_quota,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 0, 0, 0),
      ends_at: Time.utc(2026, 8, 11, 0, 0, 0),
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

  it 'moves booking in place and adjusts remaining' do
    described_class.call(
      booking: booking,
      quota: quota,
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 5, 0)
    )

    booking.reload
    expect(booking.starts_at).to eq(Time.utc(2026, 8, 10, 12, 0, 0))
    expect(booking.seconds).to eq(300)
    expect(quota.reload.seconds_remaining).to eq(3_300)
  end

  it 'keeps original booking when target slot is busy (AE3)' do
    Airtime::Book.call(
      quota: quota.reload,
      organization: organization,
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 10, 0)
    )
    original_starts = booking.starts_at
    original_remaining = quota.reload.seconds_remaining

    expect do
      described_class.call(
        booking: booking,
        quota: quota,
        starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 10, 0)
      )
    end.to raise_error(Airtime::ConflictError)

    expect(booking.reload.starts_at).to eq(original_starts)
    expect(quota.reload.seconds_remaining).to eq(original_remaining)
  end

  it 'invalidates linked media plan when new window no longer covers it (KTD4)' do
    plan = create(
      :media_plan,
      organization: organization,
      broadcast_point_group: group,
      airtime_booking: booking,
      starts_at: booking.starts_at,
      ends_at: booking.ends_at
    )

    described_class.call(
      booking: booking,
      quota: quota,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 10, 5, 0)
    )

    expect(booking.reload.ends_at).to eq(Time.utc(2026, 8, 10, 10, 5, 0))
    expect(plan.reload).to be_invalidated
  end
end
