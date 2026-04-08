# frozen_string_literal: true

FactoryBot.define do
  factory :broadcast_point do
    organization
    sequence(:name) { |n| "Broadcast point #{n}" }
    status { :unknown }
  end
end
