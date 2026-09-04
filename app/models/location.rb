# frozen_string_literal: true

# == Schema Information
#
# Table name: locations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  operating_hours :jsonb            not null
#  time_zone       :string           default("UTC"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_locations_on_name  (name) UNIQUE
#
class Location < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name operating_hours time_zone created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[]
  end

  include Location::OperatingHours

  has_many :stations, dependent: :destroy
  has_many :screens, through: :stations

  validates :name, presence: true, uniqueness: true
  validates :time_zone, presence: true
  validate :operating_hours_shape

  def operating_hours=(value)
    super(Location::OperatingHours.normalize(value))
  end
end
