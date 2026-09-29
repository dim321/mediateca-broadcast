# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::AddClip do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:organization, :operator) }
  let(:user) { create(:user, :manager, organization: operator) }
  let(:theme) { ServiceThemes::Create.call(organization: operator, name: "Салон красоты") }
  let(:png) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/1x1.png"), "image/png") }

  it "stores a service clip asset without adding it to the theme folder" do
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait,
      rotation: theme.welcome_rotation)

    travel_to(Time.utc(2026, 9, 2, 12, 0, 0)) do
      expect {
        described_class.call(theme: theme, role: :welcome, file: png, uploaded_by: user)
      }.to change(MediaAsset, :count).by(1)
        .and not_change(RotationItem, :count)
    end

    asset = MediaAsset.last
    expect(asset).to have_attributes(
      content_type: "service",
      visibility: "network",
      organization: operator,
      uploaded_by: user
    )
    expect(theme.welcome_rotation.rotation_items.find_by(media_asset: asset)).to be_nil
  end

  it "rejects an unknown role" do
    expect {
      described_class.call(theme: theme, role: :commercial, file: png, uploaded_by: user)
    }.to raise_error(ArgumentError)
  end
end
