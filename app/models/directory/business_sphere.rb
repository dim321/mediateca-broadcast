# frozen_string_literal: true

# == Schema Information
#
# Table name: directory_business_spheres
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_directory_business_spheres_on_lower_name  (lower((name)::text)) UNIQUE
#
class Directory::BusinessSphere < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[]
  end

  has_many :profiles, foreign_key: :business_sphere_id, inverse_of: :business_sphere,
    dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
