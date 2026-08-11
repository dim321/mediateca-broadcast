# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssetsHelper, type: :helper do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  describe "#media_asset_broadcast_placeholder" do
    it "returns N/A for non-video" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq(I18n.t("media_assets.index.broadcast_na"))
    end

    it "returns Processing… for video without broadcast_file while processing" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "processing")
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq(I18n.t("media_assets.index.broadcast_processing"))
    end

    it "returns humanized status for failed video without broadcast_file" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "failed")
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq("Failed")
    end
  end

  describe "#media_asset_broadcast_cell" do
    it "links to broadcast_file when attached" do
      asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready, organization: organization, uploaded_by: user)
      html = helper.media_asset_broadcast_cell(asset)
      expect(html).to include("source.ts")
      expect(html).to include("disposition=attachment")
    end

    it "shows placeholder text when broadcast_file missing" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_broadcast_cell(asset)).to eq(I18n.t("media_assets.index.broadcast_na"))
    end
  end

  describe "#media_asset_source_link" do
    it "links to the original file" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      html = helper.media_asset_source_link(asset)
      expect(html).to include("1x1.png")
      expect(html).to include("disposition=attachment")
    end
  end

  describe "#media_asset_select_label" do
    it "joins source filename and broadcast label" do
      asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_select_label(asset)).to eq("source.mp4 · source.ts")
    end

    it "joins source filename and Processing… when video is encoding" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "processing")
      expect(helper.media_asset_select_label(asset)).to eq(
        "source.mp4 · #{I18n.t('media_assets.index.broadcast_processing')}"
      )
    end
  end
end
