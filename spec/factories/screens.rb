# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  orientation     :string           default("landscape"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#  station_id      :bigint           not null
#
# Indexes
#
#  index_screens_on_organization_id                          (organization_id)
#  index_screens_on_organization_id_and_station_id_and_name  (organization_id,station_id,name) UNIQUE
#  index_screens_on_station_id                               (station_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (station_id => stations.id)
#
FactoryBot.define do
  factory :screen do
    organization
    station { association(:station, organization: organization) }
    sequence(:name) { |n| "Screen #{n}" }
    orientation { :landscape }
  end
end
