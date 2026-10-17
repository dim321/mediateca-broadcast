# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::StreamChannels::Reconcile do
  def digest(seed)
    Digest::SHA256.hexdigest(seed)
  end

  it "keeps an existing port and gives the smallest free port to a new digest" do
    station = create(:station)
    kept = digest("kept")
    create(:station_stream_channel, station:, timeline_digest: digest("gone"), stream_port: 8091)
    create(:station_stream_channel, station:, timeline_digest: kept, stream_port: 8092)

    ports = described_class.call(
      station:,
      digests_by_screen_id: { 7 => kept, 8 => digest("fresh") },
      horizon_complete: true
    )

    expect(ports).to eq(7 => 8092, 8 => 8091)
    expect(station.stream_channels.order(:stream_port).pluck(:timeline_digest, :stream_port)).to eq(
      [ [ digest("fresh"), 8091 ], [ kept, 8092 ] ]
    )
  end

  it "assigns the same port to every screen that shares a digest" do
    station = create(:station)
    shared = digest("shared")

    ports = described_class.call(
      station:,
      digests_by_screen_id: { 7 => shared, 8 => shared },
      horizon_complete: true
    )

    expect(ports).to eq(7 => 8091, 8 => 8091)
    expect(station.stream_channels.count).to eq(1)
  end

  it "does not change rows when the same digests are reconciled again" do
    station = create(:station)
    shared = digest("shared")
    described_class.call(station:, digests_by_screen_id: { 7 => shared }, horizon_complete: true)

    expect {
      described_class.call(station:, digests_by_screen_id: { 7 => shared }, horizon_complete: true)
    }.not_to change { station.stream_channels.order(:id).pluck(:timeline_digest, :stream_port, :updated_at) }
  end

  it "does not insert or delete while the horizon is incomplete" do
    station = create(:station)
    stored = digest("stored")
    create(:station_stream_channel, station:, timeline_digest: stored, stream_port: 8094)

    matched = described_class.call(
      station:,
      digests_by_screen_id: { 7 => stored },
      horizon_complete: false
    )
    unmatched = described_class.call(
      station:,
      digests_by_screen_id: { 8 => digest("new") },
      horizon_complete: false
    )

    expect(matched).to eq(7 => 8094)
    expect(unmatched).to eq({})
    expect(station.stream_channels.pluck(:timeline_digest, :stream_port)).to eq([ [ stored, 8094 ] ])
  end

  it "leaves a new digest without a port when the pool is full" do
    station = create(:station)
    pool = StationStreamChannel::PORT_POOL.to_a
    kept = pool.index_with { |port| digest("kept-#{port}") }
    kept.each { |port, timeline_digest| create(:station_stream_channel, station:, timeline_digest:, stream_port: port) }
    digests = kept.values.each_with_index.to_h { |timeline_digest, index| [ index + 1, timeline_digest ] }
    digests[999] = digest("overflow")

    ports = described_class.call(station:, digests_by_screen_id: digests, horizon_complete: true)

    expect(ports[999]).to be_nil
    expect(ports[1]).to eq(8091)
    expect(station.stream_channels.count).to eq(100)
  end
end
