# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tag, type: :model do
  describe "validations" do
    it "requires a name" do
      tag = build(:tag, name: "")
      expect(tag).not_to be_valid
    end

    it "enforces case-insensitive unique name per organization" do
      org = create(:organization)
      create(:tag, organization: org, name: "Retail")
      dup = build(:tag, organization: org, name: "retail")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "allows same name in another organization" do
      create(:tag, name: "Shared")
      other = build(:tag, organization: create(:organization), name: "Shared")
      expect(other).to be_valid
    end

    it "strips whitespace on the name" do
      tag = create(:tag, name: "  metro  ")
      expect(tag.reload.name).to eq("metro")
    end
  end
end
