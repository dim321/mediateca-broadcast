# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id              :bigint           not null, primary key
#  email           :string           not null
#  password_digest :string           not null
#  role            :string           default("manager"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_users_on_email            (email) UNIQUE
#  index_users_on_organization_id  (organization_id)
#  index_users_on_role             (role)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class User < ApplicationRecord
  belongs_to :organization, inverse_of: :users

  has_many :created_advertising_orders, class_name: "AdvertisingOrder",
    foreign_key: :created_by_user_id, inverse_of: :created_by, dependent: :restrict_with_exception

  has_secure_password

  enum :role, {
    manager: "manager",
    accountant: "accountant",
    administrator: "administrator"
  }, default: :manager

  validates :email, presence: true, uniqueness: { case_sensitive: true },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true
  normalizes :email, with: ->(e) { e.strip.downcase }
end
