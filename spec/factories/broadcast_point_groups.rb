# frozen_string_literal: true

FactoryBot.define do
  factory :broadcast_point_group do
    organization
    sequence(:name) { |n| "Screen group #{n}" }
  end
end
