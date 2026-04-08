# frozen_string_literal: true

FactoryBot.define do
  factory :schedule_target do
    schedule_rule
    point_group { association :point_group, organization: schedule_rule.organization }
  end
end
