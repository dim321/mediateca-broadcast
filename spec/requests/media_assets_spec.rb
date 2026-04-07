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
          media_asset: { file: fixture_file_upload("spec/fixtures/files/bad.txt", "text/plain") }
        }
      end.not_to change(MediaAsset, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates an asset for a valid upload" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      expect do
        post media_assets_path, params: {
          media_asset: { file: fixture_file_upload(png, "image/png") }
        }
      end.to change(MediaAsset, :count).by(1)
      expect(response).to redirect_to(media_assets_path)
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
