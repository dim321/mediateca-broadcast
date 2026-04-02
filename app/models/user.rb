# frozen_string_literal: true

class User < ApplicationRecord
  belongs_to :organization, inverse_of: :users

  has_secure_password

  validates :email, presence: true, uniqueness: { case_sensitive: true },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email, with: ->(e) { e.strip.downcase }
end
