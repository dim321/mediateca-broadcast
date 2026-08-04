# frozen_string_literal: true

# == Schema Information
#
# Table name: media_plans
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  starts_at                :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_media_plans_on_broadcast_point_group_id                   (broadcast_point_group_id)
#  index_media_plans_on_organization_id                            (organization_id)
#  index_media_plans_on_organization_id_and_starts_at_and_ends_at  (organization_id,starts_at,ends_at)
#  index_media_plans_on_rotation_id                                (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
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
