# frozen_string_literal: true

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
class PlaylistItem < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id position offset_seconds duration_seconds source_kind created_at updated_at playlist_id media_asset_id media_plan_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[playlist media_asset media_plan screens]
  end

  belongs_to :playlist, inverse_of: :items
  belongs_to :media_asset
  belongs_to :media_plan, optional: true

  has_many :playlist_item_screens, dependent: :destroy, inverse_of: :playlist_item, autosave: true
  has_many :screens, through: :playlist_item_screens

  enum :source_kind, {
    media_plan: "media_plan",
    filler: "filler",
    insertion: "insertion",
    service: "service"
  }

  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :playlist_id }
  validates :offset_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :media_plan_id, presence: true, if: :media_plan?
  validate :must_have_screens

  private

  def must_have_screens
    return if playlist_item_screens.any? || screens.any?

    errors.add(:screens, :blank)
  end
end
