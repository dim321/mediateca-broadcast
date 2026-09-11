# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe Directory::BusinessSphere, type: :model do
  describe "validations" do
    it "requires a name" do
      sphere = described_class.new(name: "")
      expect(sphere).not_to be_valid
      expect(sphere.errors[:name]).to be_present
    end

    it "enforces case-insensitive unique name globally" do
      create(:directory_business_sphere, name: "Retail")
      dup = described_class.new(name: "retail")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "strips whitespace on the name" do
      sphere = create(:directory_business_sphere, name: "  Ритейл  ")
      expect(sphere.reload.name).to eq("Ритейл")
    end

    it "enforces unique lower(name) at the database" do
      create(:directory_business_sphere, name: "Retail")
      expect {
        described_class.insert!(
          { name: "RETAIL", created_at: Time.current, updated_at: Time.current }
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it "restricts destroy when a profile uses the sphere" do
      sphere = create(:directory_business_sphere)
      create(:profile, business_sphere: sphere)

      expect { sphere.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end
end
