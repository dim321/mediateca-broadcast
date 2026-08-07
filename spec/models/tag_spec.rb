# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: tags
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_tags_on_lower_name  (lower((name)::text)) UNIQUE
#
RSpec.describe Tag, type: :model do
  describe "validations" do
    it "requires a name" do
      tag = build(:tag, name: "")
      expect(tag).not_to be_valid
    end

    it "enforces case-insensitive unique name globally" do
      create(:tag, name: "Retail")
      dup = build(:tag, name: "retail")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "strips whitespace on the name" do
      tag = create(:tag, name: "  metro  ")
      expect(tag.reload.name).to eq("metro")
    end
  end
end
