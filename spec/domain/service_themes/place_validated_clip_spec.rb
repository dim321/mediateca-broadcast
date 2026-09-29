# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::PlaceValidatedClip do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:organization, :operator) }
  let(:user) { create(:user, :traffic_manager, organization: operator) }
  let(:theme) { ServiceThemes::Create.call(organization: operator, name: "Салон красоты") }
  let(:asset) do
    create(:media_asset, :ready, :with_png_file, :content_validated,
      organization: operator, content_type: "service", visibility: "network", uploaded_by: user)
  end

  it "adds a validated service clip and regenerates playlists" do
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, rotation: theme.welcome_rotation)

    travel_to(Time.utc(2026, 9, 28, 12, 0, 0)) do
      expect {
        described_class.call(theme: theme, role: :welcome, media_asset: asset)
      }.to change(RotationItem, :count).by(1)
        .and have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-28")
    end
  end

  it "rejects an unmarked service clip" do
    unmarked = create(:media_asset, :ready, :with_png_file, organization: operator, content_type: "service", visibility: "network")

    expect {
      described_class.call(theme: theme, role: :welcome, media_asset: unmarked)
    }.to raise_error(MediaAssets::Error, I18n.t("media_assets.content_validation.not_validated"))
  end

  it "rejects an unknown role" do
    expect {
      described_class.call(theme: theme, role: :nope, media_asset: asset)
    }.to raise_error(ArgumentError)
  end
end
