# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedBroadcastPointGroups', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:owned_screen) { create(:screen, owner_organization: organization) }
  let(:fleet_screen) { create(:screen) }

  describe 'POST /owned_broadcast_point_groups' do
    it 'is not routed in the client cabinet' do
      expect do
        Rails.application.routes.recognize_path('/owned_broadcast_point_groups', method: :post)
      end.to raise_error(ActionController::RoutingError)
    end
  end

  describe 'GET /owned_broadcast_point_groups/new' do
    it 'does not expose a create form' do
      sign_in_as(user)

      get '/owned_broadcast_point_groups/new'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /owned_broadcast_point_groups' do
    it 'lists only groups of the current organization' do
      sign_in_as(user)
      create(:broadcast_point_group, organization: organization, name: 'Mine')
      create(:broadcast_point_group, name: 'OtherOrg')

      get owned_broadcast_point_groups_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mine')
      expect(response.body).not_to include('OtherOrg')
      expect(response.body).not_to include('/owned_broadcast_point_groups/new')
    end
  end

  describe 'POST /owned_broadcast_point_groups/:id/add_screens' do
    let!(:group) { create(:broadcast_point_group, organization: organization) }

    it 'adds an owned screen' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [ owned_screen.id ] }
      expect(group.reload.screens).to contain_exactly(owned_screen)
    end

    it 'rejects fleet screens not owned by the organization' do
      sign_in_as(user)
      post add_screens_owned_broadcast_point_group_path(group), params: { screen_ids: [ fleet_screen.id ] }
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
