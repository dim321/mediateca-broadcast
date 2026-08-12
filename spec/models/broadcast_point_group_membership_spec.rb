# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastPointGroupMembership, type: :model do
  describe 'commercial quota gates on add' do
    let(:owner) { create(:organization, :client) }
    let(:location_with_hours) do
      day = [ { 'start' => '00:00', 'end' => '23:59' } ]
      create(
        :location,
        operating_hours: {
          'mon' => day, 'tue' => day, 'wed' => day, 'thu' => day,
          'fri' => day, 'sat' => day, 'sun' => day
        }
      )
    end
    let(:group) do
      create(
        :broadcast_point_group,
        organization: owner,
        commercial_quota_percent: 60,
        commercial_quota_period: :hour
      )
    end

    it 'allows adding an owned screen whose location has operating hours' do
      screen = create(:screen, station: create(:station, location: location_with_hours), owner_organization: owner)
      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).to be_valid
    end

    it 'rejects a screen without owner matching the group when quota is set' do
      screen = create(:screen, station: create(:station, location: location_with_hours))
      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).not_to be_valid
      expect(membership.errors[:screen]).to be_present
    end

    it 'rejects an owned screen whose location lacks operating hours when quota is set' do
      bare = create(:location, operating_hours: {})
      screen = create(:screen, station: create(:station, location: bare), owner_organization: owner)
      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).not_to be_valid
      expect(membership.errors[:screen]).to be_present
    end

    it 'does not apply quota membership gates when group has no quota' do
      plain = create(:broadcast_point_group, organization: owner)
      screen = create(:screen, station: create(:station, location: create(:location, operating_hours: {})))
      membership = build(:broadcast_point_group_membership, broadcast_point_group: plain, screen: screen)

      expect(membership).to be_valid
    end
  end
end
