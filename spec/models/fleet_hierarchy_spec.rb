# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'fleet hierarchy', type: :model do
  it 'creates a location, station, and portrait screen' do
    location = Location.create!(name: 'Central Mall')
    station = Station.create!(location:, name: 'Lobby player')
    screen = Screen.create!(
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
      location: Location.create!(name: 'Central Mall'),
      name: 'Lobby player'
    )

    expect(station.offline_cache_hours).to eq(24)
  end

  it 'requires a station for a screen' do
    screen = Screen.new(
      name: 'Entrance display',
      orientation: :landscape
    )

    expect(screen).not_to be_valid
    expect(screen.errors[:station]).to be_present
  end

  it 'allows tagging a screen with a global tag' do
    screen = create(:screen)
    tag = create(:tag, name: 'Lobby')

    join = ScreenTag.create!(screen:, tag:)

    expect(screen.tags).to contain_exactly(tag)
    expect(join).to be_persisted
  end
end
