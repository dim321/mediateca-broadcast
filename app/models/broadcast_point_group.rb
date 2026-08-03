# frozen_string_literal: true

class BroadcastPointGroup < ApplicationRecord
  belongs_to :organization

  has_many :broadcast_point_group_memberships, dependent: :destroy
  has_many :screens, through: :broadcast_point_group_memberships
  has_many :media_plans, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
