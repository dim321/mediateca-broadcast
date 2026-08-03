# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    time_zone { 'UTC' }

    trait :operator do
      kind { :operator }
    end

    trait :client do
      kind { :client }
    end
  end
end
