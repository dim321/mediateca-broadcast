# frozen_string_literal: true

require "rails_helper"

RSpec.describe RotationItem, type: :model do
  describe "validations" do
    it "assigns the next position on create" do
      rotation = create(:rotation)
      first = create(:rotation_item, rotation: rotation)
      second = create(:rotation_item, rotation: rotation)
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(2)
    end

    it "rejects a media asset that is not ready" do
      rotation = create(:rotation)
      asset = create(:media_asset, :with_png_file, processing_status: "pending", organization: rotation.organization)
      item = build(:rotation_item, rotation: rotation, media_asset: asset, position: 1)
      expect(item).not_to be_valid
      expect(item.errors[:media_asset]).to be_present
    end

    it "rejects a media asset from another organization" do
      rotation = create(:rotation)
      other_asset = create(:media_asset, :ready, :with_png_file)
      item = build(:rotation_item, rotation: rotation, media_asset: other_asset, position: 1)
      expect(item).not_to be_valid
      expect(item.errors[:media_asset]).to be_present
    end

    it "rejects duplicate media_asset_id in the same rotation" do
      rotation = create(:rotation)
      asset = create(:media_asset, :ready, :with_png_file, organization: rotation.organization)
      create(:rotation_item, rotation: rotation, media_asset: asset, position: 1)
      dup = build(:rotation_item, rotation: rotation, media_asset: asset, position: 2)
      expect(dup).not_to be_valid
    end
  end
end
