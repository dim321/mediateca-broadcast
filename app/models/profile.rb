# frozen_string_literal: true

# == Schema Information
#
# Table name: profiles
#
#  id                 :bigint           not null, primary key
#  brand              :string
#  holding            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  business_sphere_id :bigint
#  organization_id    :bigint           not null
#
# Indexes
#
#  index_profiles_on_business_sphere_id  (business_sphere_id)
#  index_profiles_on_organization_id     (organization_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (business_sphere_id => directory_business_spheres.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => cascade
#
class Profile < ApplicationRecord
  belongs_to :organization, inverse_of: :profile
  belongs_to :business_sphere, class_name: "Directory::BusinessSphere", optional: true,
    inverse_of: :profiles

  validates :organization_id, uniqueness: true
end
