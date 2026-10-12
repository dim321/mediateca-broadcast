# frozen_string_literal: true

# == Schema Information
#
# Table name: station_tv_monitors
#
#  id                            :bigint           not null, primary key
#  auto_restart_when_not_playing :boolean          default(TRUE), not null
#  health_interval_seconds       :integer          default(30), not null
#  telemetry_interval_seconds    :integer          default(60), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  station_id                    :bigint           not null
#
# Indexes
#
#  index_station_tv_monitors_on_station_id  (station_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id)
#
FactoryBot.define do
  factory :station_tv_monitor do
    station
    health_interval_seconds { 30 }
    auto_restart_when_not_playing { true }
    telemetry_interval_seconds { 60 }
  end
end
