# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_point_tags
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  broadcast_point_id :bigint           not null
#  tag_id             :bigint           not null
#
# Indexes
#
#  index_broadcast_point_tags_on_broadcast_point_id             (broadcast_point_id)
#  index_broadcast_point_tags_on_broadcast_point_id_and_tag_id  (broadcast_point_id,tag_id) UNIQUE
#  index_broadcast_point_tags_on_tag_id                         (tag_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_id => broadcast_points.id)
#  fk_rails_...  (tag_id => tags.id)
#
FactoryBot.define do
  factory :broadcast_point_tag do
    broadcast_point
    tag do
      association :tag, organization: broadcast_point.organization
    end
  end
end
