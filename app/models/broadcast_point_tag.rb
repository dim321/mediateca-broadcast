# frozen_string_literal: true

class BroadcastPointTag < ApplicationRecord
  belongs_to :broadcast_point
  belongs_to :tag

  validate :same_organization

  private

  def same_organization
    return if broadcast_point.blank? || tag.blank?
    return if broadcast_point.organization_id == tag.organization_id

    errors.add(:base, :organization_mismatch)
  end
end
