# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlist, type: :model do
  describe "validations" do
    it "requires a name" do
      playlist = build(:playlist, name: "")
      expect(playlist).not_to be_valid
      expect(playlist.errors[:name]).to be_present
    end

    it "enforces unique name per organization" do
      existing = create(:playlist, name: "Morning")
      dup = build(:playlist, organization: existing.organization, name: "Morning")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to be_present
    end

    it "allows the same name in another organization" do
      a = create(:playlist, name: "Shared")
      b = build(:playlist, organization: create(:organization), name: "Shared")
      expect(b).to be_valid
    end
  end

  describe "#ordered_items" do
    it "returns items in position order" do
      playlist = create(:playlist)
      second = create(:playlist_item, playlist: playlist, position: 2)
      first = create(:playlist_item, playlist: playlist, position: 1)
      expect(playlist.ordered_items.map(&:id)).to eq([ first.id, second.id ])
    end
  end
end
