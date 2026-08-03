# frozen_string_literal: true

FactoryBot.define do
  factory :rotation do
    organization
    sequence(:name) { |n| "Rotation #{n}" }
  end
end
