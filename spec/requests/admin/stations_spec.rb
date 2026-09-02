# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin stations", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:location) { create(:location) }

  before { sign_in_as(operator) }

  it "copies the default portrait onto a newly created station" do
    template = create(:broadcast_portrait, :default, name: "Grid")
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: template, position: 1)

    expect {
      post admin_stations_path, params: {
        station: { location_id: location.id, name: "Lobby", offline_cache_hours: 24 }
      }
    }.to change(Station, :count).by(1)

    station = Station.find_by!(name: "Lobby")
    expect(response).to redirect_to(admin_station_path(station))
    expect(station.broadcast_portrait.name).to eq("Grid")
    expect(station.broadcast_portrait.blocks.map(&:kind)).to eq(%w[commercial])
    expect(station.broadcast_portrait.is_default).to be(false)
  end

  it "still creates the station when there is no default template" do
    post admin_stations_path, params: {
      station: { location_id: location.id, name: "Lobby", offline_cache_hours: 24 }
    }

    station = Station.find_by!(name: "Lobby")
    expect(response).to redirect_to(admin_station_path(station))
    expect(station.broadcast_portrait).to be_nil
  end
end
