# frozen_string_literal: true

class PointGroup < ApplicationRecord
  belongs_to :organization

  has_many :point_group_memberships, dependent: :destroy
  has_many :broadcast_points, through: :point_group_memberships
  has_many :schedule_targets, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id }
end
