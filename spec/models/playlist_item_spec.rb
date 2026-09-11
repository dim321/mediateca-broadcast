# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: playlist_items
#
#  id               :bigint           not null, primary key
#  duration_seconds :integer          not null
#  offset_seconds   :integer          not null
#  position         :integer          not null
#  source_kind      :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  media_asset_id   :bigint           not null
#  media_plan_id    :bigint
#  playlist_id      :bigint           not null
#
# Indexes
#
#  index_playlist_items_on_media_asset_id         (media_asset_id)
#  index_playlist_items_on_media_plan_id          (media_plan_id)
#  index_playlist_items_on_playlist_and_position  (playlist_id,position) UNIQUE
#  index_playlist_items_on_playlist_id            (playlist_id)
#
# Foreign Keys
#
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (media_plan_id => media_plans.id) ON DELETE => nullify
#  fk_rails_...  (playlist_id => playlists.id) ON DELETE => cascade
#
RSpec.describe PlaylistItem, type: :model do
  describe "validations" do
    it "requires a positive unique position per playlist" do
      existing = create(:playlist_item)
      duplicate = build(
        :playlist_item,
        playlist: existing.playlist,
        position: existing.position
      )
      zero = build(:playlist_item, position: 0)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:position]).to be_present
      expect(zero).not_to be_valid
      expect(zero.errors[:position]).to be_present
    end

    it "rejects a negative offset" do
      item = build(:playlist_item, offset_seconds: -1)

      expect(item).not_to be_valid
      expect(item.errors[:offset_seconds]).to be_present
    end

    it "rejects a non-positive duration" do
      item = build(:playlist_item, duration_seconds: 0)

      expect(item).not_to be_valid
      expect(item.errors[:duration_seconds]).to be_present
    end

    it "requires a media plan when source_kind is media_plan" do
      item = build(:playlist_item, source_kind: :media_plan, media_plan: nil)

      expect(item).not_to be_valid
      expect(item.errors[:media_plan_id]).to be_present
    end

    it "allows a nil media plan for filler" do
      expect(build(:playlist_item, source_kind: :filler, media_plan: nil)).to be_valid
    end

    it "requires at least one screen" do
      item = build(:playlist_item)
      item.playlist_item_screens.clear

      expect(item).not_to be_valid
      expect(item.errors[:screens]).to be_present
    end
  end

  describe "associations" do
    it "exposes screens through playlist_item_screens" do
      item = create(:playlist_item)

      expect(item.screens).to be_present
      expect(item.screens).to all(have_attributes(station_id: item.playlist.station_id))
    end

    it "destroys screen joins with the item" do
      item = create(:playlist_item)

      expect { item.destroy! }.to change(PlaylistItemScreen, :count).by(-1)
    end

    it "restricts destroying a media asset referenced by a playlist item" do
      item = create(:playlist_item)

      expect { item.media_asset.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end
end
