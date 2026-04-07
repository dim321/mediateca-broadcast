# frozen_string_literal: true

class BroadcastPoint < ApplicationRecord
  attr_accessor :new_tag_names

  belongs_to :organization

  has_many :broadcast_point_tags, dependent: :destroy
  has_many :tags, through: :broadcast_point_tags
  has_many :point_group_memberships, dependent: :destroy
  has_many :point_groups, through: :point_group_memberships

  enum :status, {
    online: "online",
    offline: "offline",
    unknown: "unknown"
  }, default: :unknown

  validates :name, presence: true
end
