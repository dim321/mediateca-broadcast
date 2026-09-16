# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::Fingerprint do
  it "is stable for the same inputs and changes when the portrait changes" do
    station = create_playlist_station!
    filler = create_clip_rotation!(organization: create(:organization, :client))
    portrait = create_cyclic_portrait!(station, filler_rotation: filler)

    first = described_class.call(station: station, for_date: PlaylistGeneration::WEDNESDAY)
    second = described_class.call(station: station.reload, for_date: PlaylistGeneration::WEDNESDAY)

    portrait.update!(name: "Night grid")
    changed = described_class.call(station: station.reload, for_date: PlaylistGeneration::WEDNESDAY)

    expect(first).to eq(second)
    expect(first).to match(/\A[0-9a-f]{64}\z/)
    expect(changed).not_to eq(first)
  end

  it "changes when block frequencies change" do
    station = create_playlist_station!
    filler = create_clip_rotation!(organization: create(:organization, :client))
    portrait = create_cyclic_portrait!(station, filler_rotation: filler, frequencies: [ 4 ])
    first = described_class.call(station: station, for_date: PlaylistGeneration::WEDNESDAY)

    portrait.update!(block_frequencies_per_hour: [ 4, 6 ])
    changed = described_class.call(station: station.reload, for_date: PlaylistGeneration::WEDNESDAY)

    expect(changed).not_to eq(first)
  end
end
