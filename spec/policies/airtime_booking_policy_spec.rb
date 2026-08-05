# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirtimeBookingPolicy do
  let(:org) { create(:organization) }
  let(:manager) { create(:user, :manager, organization: org) }
  let(:accountant) { create(:user, :accountant, organization: org) }
  let(:booking) { create(:airtime_booking, organization: org) }

  it 'allows manager to create' do
    expect(described_class.new(manager, AirtimeBooking).create?).to be true
  end

  it 'denies accountant create (AE7)' do
    expect(described_class.new(accountant, AirtimeBooking).create?).to be false
  end

  it 'scopes to tenant for manager' do
    own = create(:airtime_booking, organization: org)
    foreign = create(:airtime_booking)

    resolved = described_class::Scope.new(manager, AirtimeBooking.all).resolve
    expect(resolved).to include(own)
    expect(resolved).not_to include(foreign)
  end
end
