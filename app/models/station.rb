# frozen_string_literal: true

# == Schema Information
#
# Table name: stations
#
#  id                  :bigint           not null, primary key
#  agent_token_digest  :string
#  name                :string           not null
#  offline_cache_hours :integer          default(24), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  location_id         :bigint           not null
#
# Indexes
#
#  index_stations_on_location_id           (location_id)
#  index_stations_on_location_id_and_name  (location_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#
class Station < ApplicationRecord
  belongs_to :location

  has_many :screens, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :location_id }
  validates :offline_cache_hours, numericality: { only_integer: true, greater_than: 0 }

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
end
