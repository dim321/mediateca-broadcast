# frozen_string_literal: true

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
FactoryBot.define do
  factory :rotation_item do
    rotation
    media_asset do
      association :media_asset, :ready, :with_png_file, organization: rotation.organization
    end
  end
end
