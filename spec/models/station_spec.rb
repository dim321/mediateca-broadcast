# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: stations
#
#  id                  :bigint           not null, primary key
#  agent_token_digest  :string
#  name                :string           not null
#  offline_cache_hours :integer          default(24), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  location_id         :bigint           not null
#
# Indexes
#
#  index_stations_on_location_id           (location_id)
#  index_stations_on_location_id_and_name  (location_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#
RSpec.describe Station, type: :model do
  describe '#assign_agent_token!' do
    it 'stores a bcrypt digest and returns the token' do
      station = create(:station)

      token = station.assign_agent_token!

      expect(station.reload.agent_token_digest).to be_present
      expect(station.authenticated_with_agent_token?(token)).to be(true)
      expect(described_class.find_by_agent_token(token)).to eq(station)
    end
  end

  describe 'template_id' do
    it 'rejects a portrait that already belongs to a station' do
      station_portrait = create(:broadcast_portrait, :for_station)
      station = build(:station, template_id: station_portrait.id)

      expect(station).not_to be_valid
      expect(station.errors[:template_id]).to be_present
    end

    it 'accepts a template portrait' do
      template = create(:broadcast_portrait, :template)
      station = build(:station, template_id: template.id)

      expect(station).to be_valid
    end
  end

  describe '#next_screen_name' do
    it 'uses location and station names with the next free number' do
      location = create(:location, name: 'Локация 1')
      station = create(:station, name: 'Станция A', location: location)

      expect(station.next_screen_name).to eq('Локация 1-Станция A-screen-1')
    end

    it 'skips numbers already used on the station' do
      location = create(:location, name: 'Локация 1')
      station = create(:station, name: 'Станция A', location: location)
      create(:screen, station: station, name: 'Локация 1-Станция A-screen-1')
      create(:screen, station: station, name: 'Витрина')

      expect(station.next_screen_name).to eq('Локация 1-Станция A-screen-2')
    end
  end
end
