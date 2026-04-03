# frozen_string_literal: true

FactoryBot.define do
  factory :playlist_item do
    playlist
    media_asset do
      association :media_asset, :ready, :with_png_file, organization: playlist.organization
    end
  end
end
