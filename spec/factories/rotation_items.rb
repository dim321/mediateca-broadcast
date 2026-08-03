# frozen_string_literal: true

FactoryBot.define do
  factory :rotation_item do
    rotation
    media_asset do
      association :media_asset, :ready, :with_png_file, organization: rotation.organization
    end
  end
end
