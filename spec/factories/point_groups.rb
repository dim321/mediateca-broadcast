# frozen_string_literal: true

FactoryBot.define do
  factory :point_group do
    organization
    sequence(:name) { |n| "Point group #{n}" }
  end
end
