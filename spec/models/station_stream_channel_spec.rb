# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe StationStreamChannel, type: :model do
  it "stores one digest and one port per station inside the Voxel pool" do
    channel = create(:station_stream_channel, stream_port: 8091)

    expect(channel.stream_port).to eq(8091)
    expect(channel.timeline_digest).to match(/\A[0-9a-f]{64}\z/)
  end

  it "rejects a duplicate digest or port on the same station" do
    channel = create(:station_stream_channel, stream_port: 8091)
    same_digest = build(
      :station_stream_channel,
      station: channel.station,
      timeline_digest: channel.timeline_digest,
      stream_port: 8092
    )
    same_port = build(
      :station_stream_channel,
      station: channel.station,
      stream_port: 8091
    )

    expect(same_digest).not_to be_valid
    expect(same_port).not_to be_valid
    expect(build(:station_stream_channel, stream_port: 8091)).to be_valid
  end

  it "rejects a port outside 8091..8190 in the model and in the database" do
    channel = create(:station_stream_channel, stream_port: 8091)
    channel.stream_port = 8090

    expect(channel).not_to be_valid
    expect {
      channel.update_columns(stream_port: 8191)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "cascades when the station row is deleted" do
    foreign_key = described_class.connection.foreign_keys("station_stream_channels")
      .find { |key| key.to_table == "stations" }

    expect(foreign_key.on_delete.to_s).to eq("cascade")
  end
end
