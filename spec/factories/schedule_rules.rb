# frozen_string_literal: true

# == Schema Information
#
# Table name: schedule_rules
#
#  id               :bigint           not null, primary key
#  ends_at          :datetime         not null
#  starts_at        :datetime         not null
#  timezone_context :string           default("organization"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :bigint           not null
#  rotation_id      :bigint           not null
#
# Indexes
#
#  idx_on_organization_id_starts_at_ends_at_962bcc92ff      (organization_id,starts_at,ends_at)
#  index_schedule_rules_on_organization_id                  (organization_id)
#  index_schedule_rules_on_organization_id_and_rotation_id  (organization_id,rotation_id)
#  index_schedule_rules_on_rotation_id                      (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :schedule_rule do
    transient do
      point_group { nil }
    end

    organization
    rotation { association :rotation, organization: organization }
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
