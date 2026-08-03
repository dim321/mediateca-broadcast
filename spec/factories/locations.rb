# frozen_string_literal: true

FactoryBot.define do
  factory :location do
    organization
    sequence(:name) { |n| "Location #{n}" }
  end
end
