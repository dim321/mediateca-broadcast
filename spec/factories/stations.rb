# frozen_string_literal: true

FactoryBot.define do
  factory :station do
    organization
    location { association(:location, organization: organization) }
    sequence(:name) { |n| "Station #{n}" }
  end
end
