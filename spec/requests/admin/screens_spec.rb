# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin screens", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:location) { create(:location, name: "Локация 1") }
  let(:other_location) { create(:location, name: "Локация 2") }
  let!(:station) { create(:station, name: "Станция A", location: location) }
  let!(:other_station) { create(:station, name: "Станция B", location: other_location) }

  before { sign_in_as(operator) }

  describe "GET /admin/screens" do
    it "lists screens" do
      create(:screen, station: station, name: "Витрина 1")

      get admin_screens_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Витрина 1")
    end
  end

  describe "GET /admin/screens/new" do
    it "renders location, then station, then name, with a suggested name on stations" do
      get new_admin_screen_path

      expect(response).to have_http_status(:success)

      body = response.body
      location_pos = body.index("id=\"screen_location_id\"")
      station_pos = body.index("id=\"screen_station_id\"")
      name_pos = body.index("id=\"screen_name\"")

      expect(location_pos).to be_present.and be < station_pos
      expect(station_pos).to be < name_pos
      expect(body).to include("data-screen-location-select", 'data-auto-fill-name="true"')
      expect(body).to include("data-location-id=\"#{station.location_id}\"")
      expect(body).to include(
        "data-suggested-name=\"#{station.next_screen_name}\"",
        "data-suggested-name=\"#{other_station.next_screen_name}\""
      )
      expect(body).to include(%(selected="selected" value="#{operator_org.id}"))
    end
  end

  describe "GET /admin/screens/:id/edit" do
    it "preselects the screen location and does not auto-fill the name" do
      screen = create(:screen, station: station, name: "Витрина 1")

      get edit_admin_screen_path(screen)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-auto-fill-name="false"')
      expect(response.body).to include(%(selected="selected" value="#{location.id}"))
      expect(response.body).to include(%(selected="selected" value="#{station.id}"))
      expect(response.body).to include(%(selected="selected" value="#{operator_org.id}"))
    end
  end

  describe "POST /admin/screens" do
    it "creates a screen with an explicit name" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape"
          }
        }
      }.to change(Screen, :count).by(1)

      screen = Screen.last
      expect(screen).to have_attributes(name: "Витрина 1", station: station, owner_organization: nil)
      expect(response).to redirect_to(admin_screen_path(screen))
    end

    it "stores no owner when the operator organization is submitted" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Флот 1",
            orientation: "landscape",
            owner_organization_id: operator_org.id
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.owner_organization).to be_nil
    end

    it "assigns a client owner when a client is selected" do
      client = create(:organization, :client, name: "Командор")

      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            name: "Витрина 1",
            orientation: "landscape",
            owner_organization_id: client.id
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.owner_organization).to eq(client)
    end

    it "fills the default name when name is omitted" do
      expect {
        post admin_screens_path, params: {
          screen: {
            location_id: location.id,
            station_id: station.id,
            orientation: "landscape"
          }
        }
      }.to change(Screen, :count).by(1)

      expect(Screen.last.name).to eq("Локация 1-Станция A-screen-1")
    end
  end
end
