# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedBroadcastPointGroups', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:owned_screen) { create(:screen, owner_organization: organization) }
  let(:fleet_screen) { create(:screen) }

  describe 'POST /owned_broadcast_point_groups' do
    it 'creates a group for the organization with quota fields' do
      sign_in_as(user)

      expect do
        post owned_broadcast_point_groups_path, params: {
          broadcast_point_group: { name: 'My owner group' }
        }
      end.to change(BroadcastPointGroup, :count).by(1)

      group = BroadcastPointGroup.last
      expect(group.organization).to eq(organization)
      expect(response).to redirect_to(owned_broadcast_point_group_path(group))
    end

    it 'allows creating an empty owner group with commercial quota' do
      sign_in_as(user)

      expect do
        post owned_broadcast_point_groups_path, params: {
          broadcast_point_group: {
            name: 'Первая группа',
            commercial_quota_percent: 60,
            commercial_quota_period: 'hour'
          }
        }
      end.to change(BroadcastPointGroup, :count).by(1)

      group = BroadcastPointGroup.last
      expect(group).to have_attributes(commercial_quota_percent: 60, commercial_quota_period: 'hour')
      expect(response).to redirect_to(owned_broadcast_point_group_path(group))
    end
  end

  describe 'POST /owned_broadcast_point_groups/:id/add_screens' do
    let!(:group) { create(:broadcast_point_group, organization: organization) }

    it 'adds an owned screen' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [owned_screen.id] }
      expect(group.reload.screens).to contain_exactly(owned_screen)
    end

    it 'rejects fleet screens not owned by the organization' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [fleet_screen.id] }
      expect(group.reload.screens).to be_empty
      expect(flash[:alert]).to be_present
    end
  end

  describe 'PATCH /owned_broadcast_point_groups/:id' do
    it 'sets commercial quota when gates are satisfied' do
      sign_in_as(user)
      day_window = [ { 'start' => '09:00', 'end' => '21:00' } ]
      location = owned_screen.station.location
      location.update!(
        operating_hours: {
          'mon' => day_window, 'tue' => day_window, 'wed' => day_window,
          'thu' => day_window, 'fri' => day_window, 'sat' => day_window, 'sun' => day_window
        }
      )
      group = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: owned_screen)

      patch owned_broadcast_point_group_path(group), params: {
        broadcast_point_group: {
          name: group.name,
          commercial_quota_percent: 60,
          commercial_quota_period: 'hour'
        }
      }

      expect(response).to redirect_to(owned_broadcast_point_group_path(group))
      expect(group.reload).to have_attributes(commercial_quota_percent: 60, commercial_quota_period: 'hour')
    end
  end
end
