# frozen_string_literal: true

# == Schema Information
#
# Table name: point_group_memberships
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  broadcast_point_id :bigint           not null
#  point_group_id     :bigint           not null
#
# Indexes
#
#  index_point_group_memberships_on_broadcast_point_id  (broadcast_point_id)
#  index_point_group_memberships_on_point_group_id      (point_group_id)
#  index_point_group_memberships_unique                 (point_group_id,broadcast_point_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_id => broadcast_points.id)
#  fk_rails_...  (point_group_id => point_groups.id)
#
FactoryBot.define do
  factory :point_group_membership do
    point_group
    broadcast_point do
      association :broadcast_point, organization: point_group.organization
    end
  end
end
