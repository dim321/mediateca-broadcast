# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id                    :bigint           not null, primary key
#  name                  :string           not null
#  orientation           :string           default("landscape"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  owner_organization_id :bigint
#  station_id            :bigint           not null
#
# Indexes
#
#  index_screens_on_owner_organization_id  (owner_organization_id)
#  index_screens_on_station_id             (station_id)
#  index_screens_on_station_id_and_name    (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (owner_organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
FactoryBot.define do
  factory :screen do
    station
    sequence(:name) { |n| "Screen #{n}" }
    orientation { :landscape }

    trait :owned do
      association :owner_organization, factory: %i[organization client]
    end
  end
end
