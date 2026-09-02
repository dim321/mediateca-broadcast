# frozen_string_literal: true

# == Schema Information
#
# Table name: playlist_items
#
#  id               :bigint           not null, primary key
#  duration_seconds :integer          not null
#  offset_seconds   :integer          not null
#  position         :integer          not null
#  source_kind      :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  media_asset_id   :bigint           not null
#  media_plan_id    :bigint
#  playlist_id      :bigint           not null
#
# Indexes
#
#  index_playlist_items_on_media_asset_id         (media_asset_id)
#  index_playlist_items_on_media_plan_id          (media_plan_id)
#  index_playlist_items_on_playlist_and_position  (playlist_id,position) UNIQUE
#  index_playlist_items_on_playlist_id            (playlist_id)
#
# Foreign Keys
#
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (media_plan_id => media_plans.id) ON DELETE => nullify
#  fk_rails_...  (playlist_id => playlists.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :playlist_item do
    playlist
    media_asset { association :media_asset, :ready, :with_png_file }
    sequence(:position) { |n| n }
    offset_seconds { 0 }
    duration_seconds { 10 }
    source_kind { "filler" }

    with_screen

    trait :with_screen do
      after(:build) do |item|
        next if item.playlist_item_screens.any?

        station = item.playlist&.station
        next unless station

        screen = if station.persisted?
          station.screens.first || create(:screen, station: station)
        else
          station.screens.first || build(:screen, station: station)
        end
        item.playlist_item_screens.build(screen: screen)
      end
    end
  end
end
