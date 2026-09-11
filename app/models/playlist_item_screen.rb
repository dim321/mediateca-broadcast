# frozen_string_literal: true

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
class PlaylistItemScreen < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id created_at updated_at playlist_item_id screen_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[playlist_item screen]
  end

  belongs_to :playlist_item, inverse_of: :playlist_item_screens
  belongs_to :screen

  validates :screen_id, uniqueness: { scope: :playlist_item_id }
end
