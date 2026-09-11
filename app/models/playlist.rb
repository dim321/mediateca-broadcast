# frozen_string_literal: true

# == Schema Information
#
# Table name: playlists
#
#  id                      :bigint           not null, primary key
#  broadcast_day_starts_at :datetime
#  etag                    :string
#  fingerprint             :string
#  for_date                :date             not null
#  generated_at            :datetime
#  status                  :string           default("current"), not null
#  version                 :integer          default(1), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  station_id              :bigint           not null
#
# Indexes
#
#  index_playlists_on_station_id                    (station_id)
#  index_playlists_on_station_id_and_for_date       (station_id,for_date)
#  index_playlists_unique_current_per_station_date  (station_id,for_date) UNIQUE WHERE ((status)::text = 'current'::text)
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id) ON DELETE => restrict
#
class Playlist < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id for_date version status generated_at etag broadcast_day_starts_at fingerprint created_at updated_at station_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[station items]
  end

  belongs_to :station, inverse_of: :playlists

  has_many :items, class_name: "PlaylistItem", dependent: :destroy, inverse_of: :playlist

  enum :status, {
    current: "current",
    superseded: "superseded"
  }, default: :current

  validates :for_date, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :for_date, uniqueness: { scope: :station_id, conditions: -> { where(status: "current") } },
    if: :current?
end
