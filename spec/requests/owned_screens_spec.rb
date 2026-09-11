# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnedScreens', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:location) { create(:location) }
  let(:station) { create(:station, location: location) }

  describe 'POST /owned_screens' do
    it 'is not routed in the client cabinet' do
      expect do
        Rails.application.routes.recognize_path('/owned_screens', method: :post)
      end.to raise_error(ActionController::RoutingError)
    end
  end

  describe 'GET /owned_screens/new' do
    it 'does not expose a create form' do
      sign_in_as(user)

      get '/owned_screens/new'

      expect(response).to have_http_status(:not_found)
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
      expect(response.body).not_to include('/owned_screens/new')
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
