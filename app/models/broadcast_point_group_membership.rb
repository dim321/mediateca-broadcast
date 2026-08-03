# frozen_string_literal: true

class BroadcastPointGroupMembership < ApplicationRecord
  belongs_to :broadcast_point_group
  belongs_to :screen

  validates :screen_id, uniqueness: { scope: :broadcast_point_group_id }
end
