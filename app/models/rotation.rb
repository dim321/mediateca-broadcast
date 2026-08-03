# frozen_string_literal: true

class Rotation < ApplicationRecord
  belongs_to :organization
  has_many :rotation_items, dependent: :destroy
  has_many :media_assets, through: :rotation_items
  has_many :schedule_rules, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: true }

  def ordered_items
    rotation_items.includes(media_asset: { file_attachment: :blob }).order(:position)
  end
end
