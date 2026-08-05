# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MediaAssets", type: :request do
  let(:user) { create(:user) }

  describe "GET /" do
    it "redirects guests to login" do
      get root_path
      expect(response).to redirect_to(login_path)
    end

    it "returns success when signed in" do
      sign_in_as(user)
      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("turbo-cable-stream-source")
    end

    it "lists own assets and foreign network assets (AE8)" do
      sign_in_as(user)
      other = create(:organization)
      own = create(:media_asset, :with_png_file, organization: user.organization)
      shared = create(:media_asset, :with_png_file, :network_neutral, organization: other)
      private_foreign = create(:media_asset, :with_png_file, organization: other, visibility: :organization)

      get media_assets_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(own, :card))
      expect(response.body).to include(ActionView::RecordIdentifier.dom_id(shared, :card))
      expect(response.body).not_to include(ActionView::RecordIdentifier.dom_id(private_foreign, :card))
    end
  end

  describe "POST /media_assets" do
    before do
      sign_in_as(user)
      allow(ProcessMediaMetadataJob).to receive(:perform_later)
    end

    it "rejects unsupported files" do
      expect do
        post media_assets_path, params: {
          media_asset: {
            file: fixture_file_upload("spec/fixtures/files/bad.txt", "text/plain"),
            content_type: "own",
            visibility: "organization"
          }
        }
      end.not_to change(MediaAsset, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects upload without content_type or visibility" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      expect do
        post media_assets_path, params: {
          media_asset: { file: fixture_file_upload(png, "image/png") }
        }
      end.not_to change(MediaAsset, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates an asset for a valid upload" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      expect do
        post media_assets_path, params: {
          media_asset: {
            file: fixture_file_upload(png, "image/png"),
            content_type: "own",
            visibility: "organization"
          }
        }
      end.to change(MediaAsset, :count).by(1)
      expect(response).to redirect_to(media_assets_path)
      expect(MediaAsset.last).to have_attributes(content_type: "own", visibility: "organization")
    end
  end

  describe "PATCH /media_assets/:id (turbo_stream)" do
    before { sign_in_as(user) }

    it "returns turbo-stream replace" do
      asset = create(:media_asset, :with_png_file, organization: user.organization, uploaded_by: user)
      allow(ProcessMediaMetadataJob).to receive(:perform_later)

      patch media_asset_path(asset, format: :turbo_stream)
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end
  end
end
