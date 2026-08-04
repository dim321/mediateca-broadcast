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
class BroadcastPointTag < ApplicationRecord
  belongs_to :broadcast_point
  belongs_to :tag

  validate :same_organization

  private

  def same_organization
    return if broadcast_point.blank? || tag.blank?
    return if broadcast_point.organization_id == tag.organization_id

    errors.add(:base, :organization_mismatch)
  end
end
