# frozen_string_literal: true

FactoryBot.define do
  factory :broadcast_point_group_membership do
    broadcast_point_group
    screen { association :screen, organization: create(:organization, :operator) }
  end
end
