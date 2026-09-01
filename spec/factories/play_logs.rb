# frozen_string_literal: true

FactoryBot.define do
  factory :play_log do
    organization
    screen
    media_asset { association :media_asset, :ready, :with_png_file, organization: organization }
    started_at { Time.current }
    source { :agent }
  end
end
