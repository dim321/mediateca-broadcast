# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id              :bigint           not null, primary key
#  email           :string           not null
#  first_name      :string
#  job_title       :string
#  last_name       :string
#  location        :string
#  password_digest :string           not null
#  phone           :string
#  role            :string           default("manager"), not null
#  status          :string           default("active"), not null
#  telegram        :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_users_on_email            (email) UNIQUE
#  index_users_on_organization_id  (organization_id)
#  index_users_on_role             (role)
#  index_users_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class User < ApplicationRecord
  AVATAR_CONTENT_TYPES = %w[image/png image/jpeg image/jpg image/gif image/webp].freeze
  AVATAR_MAX_SIZE = 5.megabytes

  def self.ransackable_attributes(_auth_object = nil)
    %w[id email first_name last_name phone job_title telegram location role status created_at updated_at organization_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization]
  end

  belongs_to :organization, inverse_of: :users

  has_many :created_advertising_orders, class_name: "AdvertisingOrder",
    foreign_key: :created_by_user_id, inverse_of: :created_by, dependent: :restrict_with_exception

  has_one_attached :avatar

  has_secure_password

  enum :role, {
    manager: "manager",
    accountant: "accountant",
    administrator: "administrator"
  }, default: :manager

  enum :status, {
    active: "active",
    blocked: "blocked"
  }, default: :active

  validates :email, presence: true, uniqueness: { case_sensitive: true },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  validates :status, presence: true
  validate :avatar_must_be_image, if: -> { avatar.attached? }
  validate :avatar_size_within_limit, if: -> { avatar.attached? }

  normalizes :email, with: ->(e) { e.strip.downcase }

  def display_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  private

  def avatar_must_be_image
    return if AVATAR_CONTENT_TYPES.include?(avatar.content_type)

    errors.add(:avatar, :invalid_content_type)
  end

  def avatar_size_within_limit
    return if avatar.byte_size <= AVATAR_MAX_SIZE

    errors.add(:avatar, :too_large)
  end
end
