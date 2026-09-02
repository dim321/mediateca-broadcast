# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: playlist_item_screens
#
#  id               :bigint           not null, primary key
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  playlist_item_id :bigint           not null
#  screen_id        :bigint           not null
#
# Indexes
#
#  index_playlist_item_screens_on_item_and_screen   (playlist_item_id,screen_id) UNIQUE
#  index_playlist_item_screens_on_playlist_item_id  (playlist_item_id)
#  index_playlist_item_screens_on_screen_id         (screen_id)
#
# Foreign Keys
#
#  fk_rails_...  (playlist_item_id => playlist_items.id) ON DELETE => cascade
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#
RSpec.describe PlaylistItemScreen, type: :model do
  describe "validations" do
    it "enforces uniqueness of a screen within a playlist item" do
      existing = create(:playlist_item).playlist_item_screens.first
      duplicate = build(
        :playlist_item_screen,
        playlist_item: existing.playlist_item,
        screen: existing.screen
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:screen_id]).to be_present
    end
  end
end
