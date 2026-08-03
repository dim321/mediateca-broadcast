# frozen_string_literal: true

require "rails_helper"

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
