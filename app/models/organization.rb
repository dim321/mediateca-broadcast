# frozen_string_literal: true

class Organization < ApplicationRecord
  has_many :users, inverse_of: :organization, dependent: :restrict_with_exception
  has_many :media_assets, dependent: :restrict_with_exception
  has_many :playlists, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :time_zone, presence: true
end
