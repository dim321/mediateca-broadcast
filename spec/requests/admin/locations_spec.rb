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
          address: "ул. Красной Армии, 10",
          operating_hours: {
            mon: [ { start: "09:00", end: "21:00" } ],
            tue: [ { start: "", end: "" } ]
          }
        }
      }
    }.to change(Location, :count).by(1)

    location = Location.find_by!(name: "Mall Atrium")
    expect(location.address).to eq("ул. Красной Армии, 10")
    expect(location.operating_hours).to eq(
      "mon" => [ { "start" => "09:00", "end" => "21:00" } ]
    )
    expect(response).to redirect_to(admin_location_path(location))
  end

  it "does not create a location without an address" do
    expect {
      post admin_locations_path, params: {
        location: { name: "Mall Without Address", address: "" }
      }
    }.not_to change(Location, :count)

    expect(response).to have_http_status(:unprocessable_content)
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

  it "requires an address on the new form" do
    get new_admin_location_path

    address = Nokogiri::HTML(response.body).at_css('input[name="location[address]"]')

    expect(address).to be_present
    expect(address["required"]).to eq("required")
  end

  it "lists the address after the name" do
    location = create(:location, name: "Mall Atrium", address: "ул. Красной Армии, 10")

    get admin_locations_path

    headers = Nokogiri::HTML(response.body).at_css("table thead tr").css("th").map { |th| th.text.strip }
    row = Nokogiri::HTML(response.body).at_css("table tbody tr")

    expect(headers[0]).to include(Location.human_attribute_name(:name))
    expect(headers[1]).to eq(Location.human_attribute_name(:address))
    expect(row.text).to include(location.address)
  end

  it "shows the address after the name" do
    location = create(:location, name: "Mall Atrium", address: "ул. Красной Армии, 10")

    get admin_location_path(location)

    labels = Nokogiri::HTML(response.body).css("main dl dt").map { |node| node.text.strip }

    expect(labels[0]).to eq(Location.human_attribute_name(:name))
    expect(labels[1]).to eq(Location.human_attribute_name(:address))
    expect(response.body).to include(location.address)
  end
end
