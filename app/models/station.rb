# frozen_string_literal: true

class Station < ApplicationRecord
  belongs_to :organization
  belongs_to :location

  has_many :screens, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: %i[organization_id location_id] }
  validates :offline_cache_hours, numericality: { only_integer: true, greater_than: 0 }
  validate :location_belongs_to_organization

  private

  def location_belongs_to_organization
    return if location.blank? || location.organization_id == organization_id

    errors.add(:location, :organization_mismatch)
  end
end
