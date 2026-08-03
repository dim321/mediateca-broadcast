# frozen_string_literal: true

class Location < ApplicationRecord
  belongs_to :organization

  has_many :stations, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
