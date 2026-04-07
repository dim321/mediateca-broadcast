# frozen_string_literal: true

FactoryBot.define do
  factory :playlist do
    organization
    sequence(:name) { |n| "Playlist #{n}" }
  end
end
