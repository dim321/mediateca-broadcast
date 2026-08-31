# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe Profile, type: :model do
  describe "validations" do
    it "requires an organization" do
      profile = described_class.new
      expect(profile).not_to be_valid
      expect(profile.errors[:organization]).to be_present
    end

    it "enforces one profile per organization" do
      organization = create(:organization)
      create(:profile, organization: organization)
      duplicate = build(:profile, organization: organization)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:organization_id]).to be_present
    end

    it "allows a profile without a business sphere, brand, or holding" do
      profile = build(:profile, business_sphere: nil, brand: nil, holding: nil)
      expect(profile).to be_valid
    end
  end

  describe "associations" do
    it "belongs to an optional business sphere" do
      sphere = create(:directory_business_sphere)
      profile = create(:profile, business_sphere: sphere)

      expect(profile.business_sphere).to eq(sphere)
    end

    it "is destroyed with the organization" do
      organization = create(:organization, :with_profile)

      expect { organization.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
