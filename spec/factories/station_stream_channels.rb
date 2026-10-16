# frozen_string_literal: true

# == Schema Information
#
# Table name: station_stream_channels
#
#  id              :bigint           not null, primary key
#  stream_port     :integer          not null
#  timeline_digest :string(64)       not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  station_id      :bigint           not null
#
# Indexes
#
#  idx_on_station_id_timeline_digest_de27fa898a                 (station_id,timeline_digest) UNIQUE
#  index_station_stream_channels_on_station_id                  (station_id)
#  index_station_stream_channels_on_station_id_and_stream_port  (station_id,stream_port) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :station_stream_channel do
    station
    sequence(:timeline_digest) { |n| Digest::SHA256.hexdigest("timeline-#{n}") }
    sequence(:stream_port) { |n| 8091 + ((n - 1) % StationStreamChannel::PORT_POOL.size) }
  end
end
