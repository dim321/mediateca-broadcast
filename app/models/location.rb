# frozen_string_literal: true

# == Schema Information
#
# Table name: locations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_locations_on_organization_id           (organization_id)
#  index_locations_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class Location < ApplicationRecord
  belongs_to :organization

  has_many :stations, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
