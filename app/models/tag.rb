# frozen_string_literal: true

# == Schema Information
#
# Table name: tags
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_tags_on_lower_name  (lower((name)::text)) UNIQUE
#
class Tag < ApplicationRecord
  has_many :screen_tags, dependent: :destroy
  has_many :screens, through: :screen_tags

  validates :name, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
