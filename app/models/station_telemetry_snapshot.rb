# frozen_string_literal: true

# == Schema Information
#
# Table name: station_telemetry_snapshots
#
#  id                 :bigint           not null, primary key
#  broadcast_ok       :boolean          default(FALSE), not null
#  ignored_screen_ids :jsonb            not null
#  package_etag       :string           default(""), not null
#  reported_at        :datetime         not null
#  uptime_seconds     :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  station_id         :bigint           not null
#
# Indexes
#
#  index_station_telemetry_snapshots_on_station_id  (station_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id)
#
class StationTelemetrySnapshot < ApplicationRecord
  belongs_to :station

  validates :reported_at, :uptime_seconds, presence: true
  validates :uptime_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
