# frozen_string_literal: true

FactoryBot.define do
  factory :screen do
    organization
    station { association(:station, organization: organization) }
    sequence(:name) { |n| "Screen #{n}" }
    orientation { :landscape }
  end
end
