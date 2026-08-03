# frozen_string_literal: true

class Screen < ApplicationRecord
  belongs_to :organization
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

  validates :name, presence: true, uniqueness: { scope: %i[organization_id station_id] }
  validate :station_belongs_to_organization

  scope :operator_catalog, -> {
    joins(:organization).merge(Organization.operator)
  }

  private

  def station_belongs_to_organization
    return if station.blank? || station.organization_id == organization_id

    errors.add(:station, :organization_mismatch)
  end
end
