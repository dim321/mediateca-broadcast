# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin locations", type: :request do
  include ActiveJob::TestHelper

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  it "creates a location with weekly operating hours" do
    expect {
      post admin_locations_path, params: {
        location: {
          name: "Mall Atrium",
          operating_hours: {
            mon: [ { start: "09:00", end: "21:00" } ],
            tue: [ { start: "", end: "" } ]
          }
        }
      }
    }.to change(Location, :count).by(1)

    location = Location.find_by!(name: "Mall Atrium")
    expect(location.operating_hours).to eq(
      "mon" => [ { "start" => "09:00", "end" => "21:00" } ]
    )
    expect(response).to redirect_to(admin_location_path(location))
  end

  it "permits time_zone and enqueues regen when the zone or hours change" do
    location = create(:location, time_zone: "UTC", operating_hours: { "mon" => [ { "start" => "09:00", "end" => "21:00" } ] })
    station = create(:station, location: location)

    expect {
      patch admin_location_path(location), params: {
        location: { name: location.name, time_zone: "Asia/Krasnoyarsk" }
      }
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

    expect(location.reload.time_zone).to eq("Asia/Krasnoyarsk")
    expect(response).to redirect_to(admin_location_path(location))
  end

  it "does not enqueue regen when only the name changes" do
    location = create(:location, time_zone: "UTC")
    create(:station, location: location)

    expect {
      patch admin_location_path(location), params: { location: { name: "Renamed Mall" } }
    }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
  end

  it "shows the operating hours fields on the new form" do
    get new_admin_location_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('name="location[operating_hours][mon][][start]"')
    expect(response.body).to include(I18n.t("locations.edit.days.mon"))
    expect(response.body).to include(I18n.t("locations.edit.copy_monday_to_all"))
    expect(response.body).to include("data-operating-hours-copy-mon")
    expect(response.body).to include('data-controller="operating-hours"')
    expect(response.body).to include('name="location[time_zone]"')
  end
end
