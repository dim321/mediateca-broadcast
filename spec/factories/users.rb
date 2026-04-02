# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    organization
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123456' }
  end
end
