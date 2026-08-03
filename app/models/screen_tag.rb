# frozen_string_literal: true

class ScreenTag < ApplicationRecord
  belongs_to :screen
  belongs_to :tag

  validate :same_organization

  private

  def same_organization
    return if screen.blank? || tag.blank?
    return if screen.organization_id == tag.organization_id

    errors.add(:base, :organization_mismatch)
  end
end
