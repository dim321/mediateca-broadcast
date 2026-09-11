# frozen_string_literal: true

require "rails_helper"

RSpec.describe Airtime::ScreenOverlapGuard do
  let(:starts_at) { Time.utc(2026, 8, 10, 10, 0, 0) }
  let(:ends_at) { Time.utc(2026, 8, 10, 11, 0, 0) }
  let(:screen) { create(:screen) }
  let(:organization) { create(:organization, :client) }

  def occupy_order_claim
    line = create(
      :advertising_order_line,
      advertising_order: create(:advertising_order, organization: organization),
      screen: screen
    )
    Airtime::OccupyWithPlan.call(
      organization: organization,
      rotation: line.advertising_order.rotation,
      starts_at: starts_at,
      ends_at: ends_at,
      placement_kind: :commercial,
      shows_per_hour: 3,
      screens: [ screen ],
      order_claim: true,
      advertising_order_line: line
    )
  end

  it "ignores overlapping order-claim bookings when occupying another order claim" do
    occupy_order_claim

    expect(
      described_class.call(
        starts_at: starts_at,
        ends_at: ends_at,
        screen_ids: [ screen.id ],
        order_claim: true
      )
    ).not_to exist
  end

  it "still reports an overlapping order-claim booking for a manual occupy" do
    occupy_order_claim

    expect(
      described_class.call(
        starts_at: starts_at,
        ends_at: ends_at,
        screen_ids: [ screen.id ]
      )
    ).to exist
  end
end
