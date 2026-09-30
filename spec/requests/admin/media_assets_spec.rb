# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin media assets", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client_org) { create(:organization) }

  before { sign_in_as(operator) }

  it "renders the index with attached Active Storage files" do
    create(:media_asset, :with_png_file, :ready, organization: client_org)

    get admin_media_assets_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include("1x1.png")
  end

  it "renders a filter for each column" do
    create(:media_asset, :with_png_file, :ready, organization: client_org)

    get admin_media_assets_path

    expect(response.body).to include('name="q[filename_cont]"')
    expect(response.body).to include('name="q[organization_id_eq]"')
    expect(response.body).to include('name="q[content_kind_eq]"')
    expect(response.body).to include('name="q[content_type_eq]"')
    expect(response.body).to include('name="q[processing_status_eq]"')
    expect(response.body).to include('name="q[content_validated_eq]"')
  end

  describe "column filters" do
    before do
      matching = create(:media_asset, :with_png_file, :ready, :content_validated, organization: client_org)
      matching.file.blob.update!(filename: "gallery-clip.png")
      other_org = create(:organization, name: "Другая организация")
      other = create(:media_asset, :with_mp4_file, organization: other_org, content_type: "commercial")
      other.file.blob.update!(filename: "other-clip.mp4")
    end

    it "filters by filename" do
      get admin_media_assets_path, params: { q: { filename_cont: "GALLERY" } }

      expect(response.body).to include("gallery-clip.png")
      expect(response.body).not_to include("other-clip.mp4")
    end

    it "filters by organization" do
      get admin_media_assets_path, params: { q: { organization_id_eq: client_org.id } }

      expect(response.body).to include("gallery-clip.png")
      expect(response.body).not_to include("other-clip.mp4")
    end

    it "filters by kind, content type, status, and validation" do
      get admin_media_assets_path, params: {
        q: { content_kind_eq: "image", content_type_eq: "own", processing_status_eq: "ready", content_validated_eq: "validated" }
      }

      expect(response.body).to include("gallery-clip.png")
      expect(response.body).not_to include("other-clip.mp4")
    end

    it "filters by content type" do
      get admin_media_assets_path, params: { q: { content_type_eq: "commercial" } }

      expect(response.body).to include("other-clip.mp4")
      expect(response.body).not_to include("gallery-clip.png")
    end

    it "filters unvalidated assets" do
      get admin_media_assets_path, params: { q: { content_validated_eq: "not_validated" } }

      expect(response.body).to include("other-clip.mp4")
      expect(response.body).not_to include("gallery-clip.png")
    end
  end

  it "renders the show page for an asset with attachments" do
    media_asset = create(:media_asset, :with_png_file, :ready, organization: client_org)

    get admin_media_asset_path(media_asset)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("1x1.png")
    expect(response.body).to include("<img")
    expect(response.body).to include(I18n.t("media_assets.content_validation.not_validated"))
    expect(response.body).not_to include("mark_content_validation")
  end

  it "renders a mpegts player for a ready video" do
    media_asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: client_org)

    get admin_media_asset_path(media_asset)

    expect(response.body).to include('data-controller="media-asset-player"')
    expect(response.body).to include("source.ts")
  end

  it "lets an operator traffic manager mark a client asset" do
    sign_in_as(create(:user, :traffic_manager, organization: operator_org))
    media_asset = create(:media_asset, :ready, :with_png_file, organization: client_org)

    post mark_content_validation_admin_media_asset_path(media_asset)

    expect(response).to redirect_to(admin_media_asset_path(media_asset))
    expect(media_asset.reload.content_validated?).to be true
  end

  it "refuses the mark from an operator manager" do
    media_asset = create(:media_asset, :ready, :with_png_file, organization: client_org)

    post mark_content_validation_admin_media_asset_path(media_asset)

    expect(response).to redirect_to(admin_media_asset_path(media_asset))
    expect(flash[:alert]).to eq(I18n.t("media_assets.content_validation.forbidden"))
    expect(media_asset.reload.content_validated?).to be false
  end
end
