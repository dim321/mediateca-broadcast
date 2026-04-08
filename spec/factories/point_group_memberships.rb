# frozen_string_literal: true

FactoryBot.define do
  factory :point_group_membership do
    point_group
    broadcast_point do
      association :broadcast_point, organization: point_group.organization
    end
  end
end
