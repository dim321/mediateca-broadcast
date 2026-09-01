# frozen_string_literal: true

# == Schema Information
#
# Table name: locations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  operating_hours :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_locations_on_name  (name) UNIQUE
#
class Location < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id name operating_hours created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[]
  end

  include Location::OperatingHours

  has_many :stations, dependent: :destroy
  has_many :screens, through: :stations

  validates :name, presence: true, uniqueness: true
  validate :operating_hours_shape

  def operating_hours=(value)
    super(Location::OperatingHours.normalize(value))
  end

  private

  def operating_hours_shape
    return if operating_hours.blank?
    return errors.add(:operating_hours, :invalid) unless operating_hours.is_a?(Hash)

    operating_hours.each do |day, windows|
      unless Location::OperatingHours::DAY_KEYS.include?(day.to_s)
        errors.add(:operating_hours, :invalid)
        break
      end

      Array(windows).each do |window|
        next if window.is_a?(Hash) &&
          (window["start"] || window[:start]).to_s.match?(Location::OperatingHours::TIME_FORMAT) &&
          (window["end"] || window[:end]).to_s.match?(Location::OperatingHours::TIME_FORMAT)

        errors.add(:operating_hours, :invalid)
        break
      end
    end
  end
end
