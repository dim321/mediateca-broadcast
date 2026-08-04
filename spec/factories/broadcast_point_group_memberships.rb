# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_point_group_memberships
#
#  id                       :bigint           not null, primary key
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#  screen_id                :bigint           not null
#
# Indexes
#
#  idx_on_broadcast_point_group_id_7614dd11c4            (broadcast_point_group_id)
#  index_broadcast_point_group_memberships_on_screen_id  (screen_id)
#  index_broadcast_point_group_memberships_unique        (broadcast_point_group_id,screen_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => cascade
#  fk_rails_...  (screen_id => screens.id)
#
FactoryBot.define do
  factory :broadcast_point_group_membership do
    broadcast_point_group
    screen { association :screen, organization: create(:organization, :operator) }
  end
end
