# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: rotations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_rotations_on_organization_id           (organization_id)
#  index_rotations_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
RSpec.describe Rotation, type: :model do
  describe "validations" do
    it "requires a name" do
      rotation = build(:rotation, name: "")
      expect(rotation).not_to be_valid
      expect(rotation.errors[:name]).to be_present
    end

    it "enforces unique name per organization" do
      existing = create(:rotation, name: "Morning")
      dup = build(:rotation, organization: existing.organization, name: "Morning")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "allows the same name in another organization" do
      a = create(:rotation, name: "Shared")
      b = build(:rotation, organization: create(:organization), name: "Shared")
      expect(b).to be_valid
    end
  end

  describe "#ordered_items" do
    it "returns items in position order" do
      rotation = create(:rotation)
      second = create(:rotation_item, rotation: rotation, position: 2)
      first = create(:rotation_item, rotation: rotation, position: 1)
      expect(rotation.ordered_items.map(&:id)).to eq([ first.id, second.id ])
    end
  end
end
