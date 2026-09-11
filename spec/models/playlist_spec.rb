# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: playlists
#
#  id                      :bigint           not null, primary key
#  broadcast_day_starts_at :datetime
#  etag                    :string
#  fingerprint             :string
#  for_date                :date             not null
#  generated_at            :datetime
#  status                  :string           default("current"), not null
#  version                 :integer          default(1), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  station_id              :bigint           not null
#
# Indexes
#
#  index_playlists_on_station_id                    (station_id)
#  index_playlists_on_station_id_and_for_date       (station_id,for_date)
#  index_playlists_unique_current_per_station_date  (station_id,for_date) UNIQUE WHERE ((status)::text = 'current'::text)
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id) ON DELETE => restrict
#
RSpec.describe Playlist, type: :model do
  describe "validations" do
    it "defaults to current status and version 1" do
      playlist = create(:playlist)

      expect(playlist).to be_current
      expect(playlist.version).to eq(1)
    end

    it "allows only one current playlist per station and date" do
      existing = create(:playlist, status: :current)
      duplicate = build(:playlist, station: existing.station, for_date: existing.for_date, status: :current)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:for_date]).to be_present
    end

    it "allows a superseded playlist alongside a current one for the same date" do
      current = create(:playlist, status: :current)
      superseded = build(
        :playlist,
        station: current.station,
        for_date: current.for_date,
        status: :superseded,
        version: 2
      )

      expect(superseded).to be_valid
    end
  end

  describe "associations" do
    it "destroys items with the playlist" do
      playlist = create(:playlist)
      create(:playlist_item, playlist: playlist)

      expect { playlist.destroy! }.to change(PlaylistItem, :count).by(-1)
    end

    it "belongs to a station" do
      station = create(:station)
      playlist = create(:playlist, station: station)

      expect(playlist.station).to eq(station)
      expect(station.playlists).to include(playlist)
    end
  end
end
