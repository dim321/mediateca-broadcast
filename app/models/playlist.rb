# frozen_string_literal: true

class Playlist < ApplicationRecord
  belongs_to :organization
  has_many :playlist_items, dependent: :destroy
  has_many :media_assets, through: :playlist_items
  has_many :schedule_rules, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: true }

  def ordered_items
    playlist_items.includes(media_asset: { file_attachment: :blob }).order(:position)
  end
end
