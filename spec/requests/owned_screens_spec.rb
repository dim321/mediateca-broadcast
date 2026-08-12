# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedScreens', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:location) { create(:location) }
  let(:station) { create(:station, location: location) }

  describe 'POST /owned_screens' do
    it 'creates a screen owned by the current organization' do
      sign_in_as(user)

      expect do
        post owned_screens_path, params: {
          location_id: location.id,
          screen: { name: 'Lobby Left', orientation: 'landscape', station_id: station.id }
        }
      end.to change(Screen, :count).by(1)

      screen = Screen.last
      expect(screen.owner_organization).to eq(organization)
      expect(screen.station).to eq(station)
      expect(response).to redirect_to(owned_screen_path(screen))
    end

    it 'ignores client-supplied owner_organization_id' do
      sign_in_as(user)
      other = create(:organization, :client)

      post owned_screens_path, params: {
        location_id: location.id,
        screen: {
          name: 'Forced Owner',
          orientation: 'portrait',
          station_id: station.id,
          owner_organization_id: other.id
        }
      }

      expect(Screen.last.owner_organization).to eq(organization)
    end

    it 'rejects station that does not belong to submitted location' do
      sign_in_as(user)
      other_station = create(:station, location: create(:location))

      expect do
        post owned_screens_path, params: {
          location_id: location.id,
          screen: { name: 'Mismatch', orientation: 'landscape', station_id: other_station.id }
        }
      end.not_to change(Screen, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /owned_screens' do
    it 'lists only screens owned by the organization' do
      sign_in_as(user)
      create(:screen, owner_organization: organization, name: 'Mine')
      create(:screen, name: 'FleetOnly')
      create(:screen, owner_organization: create(:organization, :client), name: 'OtherOrg')

      get owned_screens_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mine')
      expect(response.body).not_to include('FleetOnly')
      expect(response.body).not_to include('OtherOrg')
    end

    it 'denies accountant' do
      accountant = create(:user, :accountant, organization: organization)
      sign_in_as(accountant)

      get owned_screens_path

      expect(response).to redirect_to(rails_health_check_path)
    end
  end

  describe 'PATCH /owned_screens/:id' do
    it 'updates name and orientation for owned screen' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station, name: 'Old')

      patch owned_screen_path(screen), params: {
        location_id: location.id,
        screen: { name: 'New', orientation: 'portrait', station_id: station.id }
      }

      expect(response).to redirect_to(owned_screen_path(screen))
      expect(screen.reload).to have_attributes(name: 'New', orientation: 'portrait')
    end
  end

  describe 'DELETE /owned_screens/:id' do
    it 'destroys an unused owned screen' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station)

      expect do
        delete owned_screen_path(screen)
      end.to change(Screen, :count).by(-1)

      expect(response).to redirect_to(owned_screens_path)
    end

    it 'refuses destroy when screen is in a broadcast point group' do
      sign_in_as(user)
      screen = create(:screen, owner_organization: organization, station: station)
      group = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect do
        delete owned_screen_path(screen)
      end.not_to change(Screen, :count)

      expect(response).to redirect_to(owned_screen_path(screen))
      expect(flash[:alert]).to be_present
    end
  end
end
