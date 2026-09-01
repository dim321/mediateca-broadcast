# frozen_string_literal: true

# == Schema Information
#
# Table name: rotation_items
#
#  id                       :bigint           not null, primary key
#  display_duration_seconds :integer
#  position                 :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  media_asset_id           :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_rotation_items_on_media_asset_id            (media_asset_id)
#  index_rotation_items_on_rotation_id               (rotation_id)
#  index_rotation_items_on_rotation_id_and_position  (rotation_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (rotation_id => rotations.id)
#
class RotationItem < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id display_duration_seconds position created_at updated_at media_asset_id rotation_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[rotation media_asset]
  end

  belongs_to :rotation
  belongs_to :media_asset

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :rotation_id }
  validates :media_asset_id, uniqueness: { scope: :rotation_id }
  validate :media_asset_matches_organization
  validate :media_asset_must_be_ready

  before_validation :assign_position, on: :create

  private

  def assign_position
    return if position.present? && position.positive?

    max = rotation.rotation_items.maximum(:position)
    self.position = max.to_i + 1
  end

  def media_asset_matches_organization
    return if media_asset.blank? || rotation.blank?
    return if media_asset.organization_id == rotation.organization_id
    return if media_asset.visibility_network?

    errors.add(:media_asset, :wrong_organization)
  end

  def media_asset_must_be_ready
    return if media_asset.blank?

    errors.add(:media_asset, :not_ready) unless media_asset.ready?
  end
end
