# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssets::MarkContentValidated do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, :traffic_manager, organization: organization) }

  it "sets the timestamp and the user for a ready image" do
    asset = create(:media_asset, :ready, :with_png_file, organization: organization)

    described_class.call(media_asset: asset, user: user)

    expect(asset.reload.content_validated?).to be true
    expect(asset.content_validated_by).to eq(user)
  end

  it "sets the mark for a ready video that has a broadcast file" do
    asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: organization)

    described_class.call(media_asset: asset, user: user)

    expect(asset.reload.content_validated?).to be true
  end

  it "does not change an existing mark" do
    marker = create(:user, :traffic_manager, organization: organization)
    asset = create(:media_asset, :ready, :with_png_file, :content_validated, organization: organization, uploaded_by: marker)
    stamped_at = asset.content_validated_at

    described_class.call(media_asset: asset, user: user)

    asset.reload
    expect(asset.content_validated_at).to eq(stamped_at)
    expect(asset.content_validated_by).to eq(marker)
  end

  it "refuses a video without a broadcast file" do
    asset = create(:media_asset, :ready, :with_mp4_file, organization: organization)

    expect {
      described_class.call(media_asset: asset, user: user)
    }.to raise_error(MediaAssets::Error, I18n.t("media_assets.content_validation.not_playable"))
    expect(asset.reload.content_validated?).to be false
  end

  it "refuses an asset that is not ready" do
    asset = create(:media_asset, :with_png_file, organization: organization, processing_status: "pending")

    expect {
      described_class.call(media_asset: asset, user: user)
    }.to raise_error(MediaAssets::Error)
  end
end
