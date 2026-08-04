# frozen_string_literal: true

# == Schema Information
#
# Table name: screens
#
#  id          :bigint           not null, primary key
#  name        :string           not null
#  orientation :string           default("landscape"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  station_id  :bigint           not null
#
# Indexes
#
#  index_screens_on_station_id           (station_id)
#  index_screens_on_station_id_and_name  (station_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id)
#
class Screen < ApplicationRecord
  belongs_to :station

  has_many :screen_tags, dependent: :destroy
  has_many :tags, through: :screen_tags
  has_many :play_logs, dependent: :restrict_with_exception
  has_many :broadcast_point_group_memberships, dependent: :restrict_with_exception
  has_many :broadcast_point_groups, through: :broadcast_point_group_memberships

  enum :orientation, {
    landscape: "landscape",
    portrait: "portrait"
  }, default: :landscape

  validates :name, presence: true, uniqueness: { scope: :station_id }

  scope :operator_catalog, -> { all }
end
