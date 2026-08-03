# frozen_string_literal: true

FactoryBot.define do
  factory :media_plan do
    organization
    rotation { association :rotation, organization: organization }
    broadcast_point_group { association :broadcast_point_group, organization: organization }
    starts_at { Time.utc(2026, 8, 10, 10, 0, 0) }
    ends_at { Time.utc(2026, 8, 10, 12, 0, 0) }

    after(:build) do |media_plan|
      next if media_plan.broadcast_point_group.screens.exists?

      screen = create(:screen, organization: create(:organization, :operator))
      create(:broadcast_point_group_membership, broadcast_point_group: media_plan.broadcast_point_group, screen: screen)
    end
  end
end
