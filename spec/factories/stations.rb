# frozen_string_literal: true

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
FactoryBot.define do
  factory :station do
    location
    sequence(:name) { |n| "Station #{n}" }
  end
end
