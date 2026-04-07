# frozen_string_literal: true

class PointGroupMembership < ApplicationRecord
  belongs_to :point_group
  belongs_to :broadcast_point

  validates :broadcast_point_id, uniqueness: { scope: :point_group_id }
  validate :same_organization

  private

  def same_organization
    return if point_group.blank? || broadcast_point.blank?
    return if point_group.organization_id == broadcast_point.organization_id

    errors.add(:base, :organization_mismatch)
  end
end
