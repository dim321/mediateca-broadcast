# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id          :bigint           not null, primary key
#  name        :string           not null
#  orientation :string           default("landscape"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  station_id  :bigint           not null
#
# Indexes
#
#  index_screens_on_station_id           (station_id)
#  index_screens_on_station_id_and_name  (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id)
#
FactoryBot.define do
  factory :screen do
    station
    sequence(:name) { |n| "Screen #{n}" }
    orientation { :landscape }
  end
end
