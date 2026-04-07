# frozen_string_literal: true

FactoryBot.define do
  factory :broadcast_point_tag do
    broadcast_point
    tag do
      association :tag, organization: broadcast_point.organization
    end
  end
end
