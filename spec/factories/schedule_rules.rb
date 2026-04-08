# frozen_string_literal: true

FactoryBot.define do
  factory :schedule_rule do
    transient do
      point_group { nil }
    end

    organization
    playlist { association :playlist, organization: organization }
    starts_at { Time.utc(2026, 6, 1, 10, 0, 0) }
    ends_at { Time.utc(2026, 6, 1, 12, 0, 0) }
    timezone_context { :organization }

    after(:build) do |rule, evaluator|
      org = rule.organization
      pg = evaluator.point_group || create(:point_group, organization: org)
      rule.schedule_targets.build(point_group: pg) if rule.schedule_targets.empty?
    end
  end
end
