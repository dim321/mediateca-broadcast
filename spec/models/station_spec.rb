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
#  organization_id     :bigint           not null
#
# Indexes
#
#  index_stations_on_location_id                               (location_id)
#  index_stations_on_organization_id                           (organization_id)
#  index_stations_on_organization_id_and_location_id_and_name  (organization_id,location_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (organization_id => organizations.id)
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
end
