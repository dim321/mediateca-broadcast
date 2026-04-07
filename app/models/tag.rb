# frozen_string_literal: true

class Tag < ApplicationRecord
  belongs_to :organization

  has_many :broadcast_point_tags, dependent: :destroy
  has_many :broadcast_points, through: :broadcast_point_tags

  validates :name, presence: true
  validates :name,
    uniqueness: { scope: :organization_id, case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
