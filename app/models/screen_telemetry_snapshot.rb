# frozen_string_literal: true

# == Schema Information
#
# Table name: screen_telemetry_snapshots
#
#  id                :bigint           not null, primary key
#  agent_ok          :boolean          default(FALSE), not null
#  broadcast_clients :integer          default(0), not null
#  last_error        :string
#  playing           :boolean          default(FALSE), not null
#  reachable         :boolean          default(FALSE), not null
#  reported_at       :datetime         not null
#  stream_port       :integer          default(0), not null
#  url               :string           default(""), not null
#  wakefulness       :string           default(""), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  screen_id         :bigint           not null
#  station_id        :bigint           not null
#
# Indexes
#
#  index_screen_telemetry_snapshots_on_screen_id   (screen_id) UNIQUE
#  index_screen_telemetry_snapshots_on_station_id  (station_id)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id)
#  fk_rails_...  (station_id => stations.id)
#
class ScreenTelemetrySnapshot < ApplicationRecord
  belongs_to :screen
  belongs_to :station

  validates :reported_at, presence: true
  validates :stream_port, :broadcast_clients,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
