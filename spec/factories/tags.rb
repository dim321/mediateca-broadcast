# frozen_string_literal: true

FactoryBot.define do
  factory :tag do
    organization
    sequence(:name) { |n| "tag-#{n}" }
  end
end
