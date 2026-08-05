# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: rotation_items
#
#  id                       :bigint           not null, primary key
#  display_duration_seconds :integer
#  position                 :integer          not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  media_asset_id           :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_rotation_items_on_media_asset_id            (media_asset_id)
#  index_rotation_items_on_rotation_id               (rotation_id)
#  index_rotation_items_on_rotation_id_and_position  (rotation_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (rotation_id => rotations.id)
#
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

    it "rejects a private media asset from another organization" do
      rotation = create(:rotation)
      other_asset = create(:media_asset, :ready, :with_png_file, visibility: :organization)
      item = build(:rotation_item, rotation: rotation, media_asset: other_asset, position: 1)
      expect(item).not_to be_valid
      expect(item.errors[:media_asset]).to be_present
    end

    it "allows a network-shared media asset from another organization" do
      rotation = create(:rotation)
      shared = create(:media_asset, :ready, :with_png_file, :network_neutral)
      item = build(:rotation_item, rotation: rotation, media_asset: shared, position: 1)
      expect(item).to be_valid
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
