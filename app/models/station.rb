# frozen_string_literal: true

class Station < ApplicationRecord
  belongs_to :organization
  belongs_to :location

  has_many :screens, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: %i[organization_id location_id] }
  validates :offline_cache_hours, numericality: { only_integer: true, greater_than: 0 }
  validate :location_belongs_to_organization

  def self.find_by_agent_token(token)
    return if token.blank?

    find_each.find { it.authenticated_with_agent_token?(token) }
  end

  def assign_agent_token!(token = SecureRandom.hex(32))
    update!(agent_token_digest: BCrypt::Password.create(token))
    token
  end

  def authenticated_with_agent_token?(token)
    agent_token_digest.present? && BCrypt::Password.new(agent_token_digest).is_password?(token)
  rescue BCrypt::Errors::InvalidHash
    false
  end

  private

  def location_belongs_to_organization
    return if location.blank? || location.organization_id == organization_id

    errors.add(:location, :organization_mismatch)
  end
end
