# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: airtime_bookings
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  seconds                  :integer          not null
#  starts_at                :datetime         not null
#  status                   :string           default("confirmed"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#
# Indexes
#
#  idx_on_organization_id_starts_at_ends_at_f3b48d3772  (organization_id,starts_at,ends_at)
#  index_airtime_bookings_on_broadcast_point_group_id   (broadcast_point_group_id)
#  index_airtime_bookings_on_organization_id            (organization_id)
#  index_airtime_bookings_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id)
#  fk_rails_...  (organization_id => organizations.id)
#
RSpec.describe AirtimeBooking, type: :model do
  it 'defaults to confirmed' do
    expect(build(:airtime_booking)).to be_confirmed
  end

  it 'builds without an airtime quota' do
    booking = create(:airtime_booking)

    expect(booking).to be_persisted
    expect(booking).not_to respond_to(:airtime_quota)
    expect(booking.attributes).not_to have_key('airtime_quota_id')
  end

  describe '#covers_plan?' do
    let(:organization) { create(:organization) }
    let(:group) { create(:broadcast_point_group, organization: organization) }
    let(:booking) do
      build(
        :airtime_booking,
        organization: organization,
        broadcast_point_group: group,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
      )
    end

    it 'is true when plan window is inside booking' do
      plan = build(
        :media_plan,
        organization: organization,
        broadcast_point_group: group,
        starts_at: Time.utc(2026, 8, 10, 10, 15, 0),
        ends_at: Time.utc(2026, 8, 10, 10, 45, 0)
      )
      expect(booking.covers_plan?(plan)).to be true
    end

    it 'is false when plan exceeds booking window' do
      plan = build(
        :media_plan,
        organization: organization,
        broadcast_point_group: group,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 11, 30, 0)
      )
      expect(booking.covers_plan?(plan)).to be false
    end
  end
end
