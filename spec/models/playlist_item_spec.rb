# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistItem, type: :model do
  describe "validations" do
    it "assigns the next position on create" do
      playlist = create(:playlist)
      first = create(:playlist_item, playlist: playlist)
      second = create(:playlist_item, playlist: playlist)
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(2)
    end

    it "rejects a media asset that is not ready" do
      playlist = create(:playlist)
      asset = create(:media_asset, :with_png_file, processing_status: "pending", organization: playlist.organization)
      item = build(:playlist_item, playlist: playlist, media_asset: asset, position: 1)
      expect(item).not_to be_valid
      expect(item.errors[:media_asset]).to be_present
    end

    it "rejects a media asset from another organization" do
      playlist = create(:playlist)
      other_asset = create(:media_asset, :ready, :with_png_file)
      item = build(:playlist_item, playlist: playlist, media_asset: other_asset, position: 1)
      expect(item).not_to be_valid
      expect(item.errors[:media_asset]).to be_present
    end

    it "rejects duplicate media_asset_id in the same playlist" do
      playlist = create(:playlist)
      asset = create(:media_asset, :ready, :with_png_file, organization: playlist.organization)
      create(:playlist_item, playlist: playlist, media_asset: asset, position: 1)
      dup = build(:playlist_item, playlist: playlist, media_asset: asset, position: 2)
      expect(dup).not_to be_valid
    end
  end
end
