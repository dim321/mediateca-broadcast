# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'fleet hierarchy', type: :model do
  let(:organization) { create(:organization, :operator) }

  it 'creates a location, station, and portrait screen' do
    location = Location.create!(organization:, name: 'Central Mall')
    station = Station.create!(organization:, location:, name: 'Lobby player')
    screen = Screen.create!(
      organization:,
      station:,
      name: 'Entrance display',
      orientation: :portrait
    )

    expect(screen).to be_portrait
    expect(station.screens).to contain_exactly(screen)
    expect(location.stations).to contain_exactly(station)
  end

  it 'defaults station offline cache to 24 hours' do
    station = Station.create!(
      organization:,
      location: Location.create!(organization:, name: 'Central Mall'),
      name: 'Lobby player'
    )

    expect(station.offline_cache_hours).to eq(24)
  end

  it 'requires a station for a screen' do
    screen = Screen.new(
      organization:,
      name: 'Entrance display',
      orientation: :landscape
    )

    expect(screen).not_to be_valid
    expect(screen.errors[:station]).to be_present
  end

  it 'does not allow tags from another organization' do
    screen = Screen.create!(
      organization:,
      station: Station.create!(
        organization:,
        location: Location.create!(organization:, name: 'Central Mall'),
        name: 'Lobby player'
      ),
      name: 'Entrance display',
      orientation: :landscape
    )

    join = ScreenTag.new(screen:, tag: create(:tag))

    expect(join).not_to be_valid
    expect(join.errors[:base]).to include('tag and screen must belong to the same organization')
  end
end
