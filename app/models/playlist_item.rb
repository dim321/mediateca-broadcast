# frozen_string_literal: true

class PlaylistItem < ApplicationRecord
  belongs_to :playlist
  belongs_to :media_asset

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :playlist_id }
  validates :media_asset_id, uniqueness: { scope: :playlist_id }
  validate :media_asset_matches_organization
  validate :media_asset_must_be_ready

  before_validation :assign_position, on: :create

  private

  def assign_position
    return if position.present? && position.positive?

    max = playlist.playlist_items.maximum(:position)
    self.position = max.to_i + 1
  end

  def media_asset_matches_organization
    return if media_asset.blank? || playlist.blank?
    return if media_asset.organization_id == playlist.organization_id

    errors.add(:media_asset, :wrong_organization)
  end

  def media_asset_must_be_ready
    return if media_asset.blank?

    errors.add(:media_asset, :not_ready) unless media_asset.ready?
  end
end
