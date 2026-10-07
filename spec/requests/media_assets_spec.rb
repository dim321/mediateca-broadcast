# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MediaAssets", type: :request do
  let(:user) { create(:user) }

  describe "GET /media_assets" do
    it "redirects guests to login" do
      get media_assets_path
      expect(response).to redirect_to(login_path)
    end

    it "returns success when signed in" do
      sign_in_as(user)
      get media_assets_path
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

    it "renders a media table with source and broadcast columns" do
      sign_in_as(user)
      create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
             organization: user.organization, uploaded_by: user)
      create(:media_asset, :with_png_file, :ready,
             organization: user.organization, uploaded_by: user)

      get media_assets_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("media_assets.index.columns.source"))
      expect(response.body).to include(I18n.t("media_assets.index.columns.broadcast"))
      expect(response.body).to include("source.mp4")
      expect(response.body).to include("source.ts")
      expect(response.body).to include(I18n.t("media_assets.index.broadcast_na"))
      expect(response.body).to include('id="media_assets_table"')
    end

    it "renders a filter for each column" do
      sign_in_as(user)

      get media_assets_path

      expect(response.body).to include('name="q[filename_cont]"')
      expect(response.body).to include('name="q[processing_status_eq]"')
      expect(response.body).to include('name="q[content_type_eq]"')
      expect(response.body).to include('name="q[visibility_eq]"')
      expect(response.body).to include('name="q[content_validated_eq]"')
    end

    it "filters the library by filename, content type, visibility, status, and validation" do
      sign_in_as(user)
      matching = create(:media_asset, :with_png_file, :ready, :content_validated,
        organization: user.organization, content_type: "own", visibility: "organization")
      matching.file.blob.update!(filename: "gallery-clip.png")
      other = create(:media_asset, :with_mp4_file,
        organization: user.organization, content_type: "commercial", visibility: "network")
      other.file.blob.update!(filename: "other-clip.mp4")

      get media_assets_path, params: { q: { filename_cont: "GALLERY" } }

      expect(response.body).to include("gallery-clip.png")
      expect(response.body).not_to include("other-clip.mp4")

      get media_assets_path, params: { q: { content_type_eq: "commercial", visibility_eq: "network" } }

      expect(response.body).to include("other-clip.mp4")
      expect(response.body).not_to include("gallery-clip.png")

      get media_assets_path, params: { q: { processing_status_eq: "ready", content_validated_eq: "validated" } }

      expect(response.body).to include("gallery-clip.png")
      expect(response.body).not_to include("other-clip.mp4")
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

    it "enqueues processing when storage times out after the asset is persisted" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      original_save = MediaAsset.instance_method(:save)
      allow_any_instance_of(MediaAsset).to receive(:enqueue_metadata_processing)
      allow_any_instance_of(MediaAsset).to receive(:save) do |record|
        saved = original_save.bind_call(record)
        raise Errno::ETIMEDOUT, "user specified timeout for 192.168.1.14:9010" if saved

        saved
      end

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
      expect(ProcessMediaMetadataJob).to have_received(:perform_later).with(MediaAsset.last.id)
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

    it "rejects service uploads from the client cabinet" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      expect do
        post media_assets_path, params: {
          media_asset: {
            file: fixture_file_upload(png, "image/png"),
            content_type: "service",
            visibility: "organization"
          }
        }
      end.not_to change(MediaAsset, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "prepends the asset via turbo_stream without a full redirect" do
      png = Rails.root.join("spec/fixtures/files/1x1.png")
      expect do
        post media_assets_path, params: {
          media_asset: {
            file: fixture_file_upload(png, "image/png"),
            content_type: "own",
            visibility: "organization"
          }
        }, as: :turbo_stream
      end.to change(MediaAsset, :count).by(1)

      asset = MediaAsset.last
      card_id = ActionView::RecordIdentifier.dom_id(asset, :card)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream action=\"prepend\" target=\"media_assets_tbody\"")
      expect(response.body).to include(card_id)
      expect(response.body).to include("turbo-stream action=\"replace\" target=\"media_asset_upload_form\"")
      expect(response.body).to include(I18n.t("media_assets.create.created"))
    end
  end

  describe "GET /media_assets/:id" do
    let(:traffic_manager) { create(:user, :traffic_manager, organization: user.organization) }

    it "plays a ready video from the broadcast file" do
      sign_in_as(user)
      asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: user.organization)

      get media_asset_path(asset)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-controller="media-asset-player"')
      expect(response.body).to include("source.ts")
      expect(response.body).not_to include(I18n.t("media_assets.content_validation.validated"))
    end

    it "shows an image from the original file" do
      sign_in_as(user)
      asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

      get media_asset_path(asset)

      expect(response.body).to include("1x1.png")
      expect(response.body).not_to include("media-asset-player")
    end

    it "shows the validator and the mark button to the owning traffic manager" do
      sign_in_as(traffic_manager)
      asset = create(:media_asset, :ready, :with_png_file, :content_validated, organization: user.organization)

      get media_asset_path(asset)

      expect(response.body).to include(asset.content_validated_by.display_name)
      expect(response.body).to include(I18n.t("media_assets.content_validation.validated"))
    end

    it "hides the mark button from a manager" do
      sign_in_as(user)
      asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

      get media_asset_path(asset)

      expect(response.body).not_to include(mark_content_validation_media_asset_path(asset))
    end
  end

  describe "POST mark_content_validation" do
    it "marks the asset for a traffic manager and redirects back" do
      traffic_manager = create(:user, :traffic_manager, organization: user.organization)
      sign_in_as(traffic_manager)
      asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

      post mark_content_validation_media_asset_path(asset)

      expect(response).to redirect_to(media_asset_path(asset))
      expect(asset.reload.content_validated_by).to eq(traffic_manager)
    end

    it "forbids a manager" do
      sign_in_as(user)
      asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

      post mark_content_validation_media_asset_path(asset)

      expect(response).to redirect_to(rails_health_check_path)
      expect(asset.reload.content_validated?).to be false
    end
  end

  describe "PATCH /media_assets/:id (turbo_stream)" do
    before { sign_in_as(user) }

    it "returns turbo-stream replace targeting the card tr with source and broadcast cells" do
      asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                     organization: user.organization, uploaded_by: user)
      card_id = ActionView::RecordIdentifier.dom_id(asset, :card)
      allow(ProcessMediaMetadataJob).to receive(:perform_later)

      patch media_asset_path(asset, format: :turbo_stream)

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")

      doc = Nokogiri::HTML.fragment(response.body)
      stream = doc.at_css("turbo-stream[action='replace']")
      expect(stream).to be_present
      expect(stream["target"]).to eq(card_id)

      row = stream.at_css("template tr##{card_id}")
      expect(row).to be_present
      expect(row.text).to include("source.mp4")
      expect(row.text).to include("source.ts")
    end
  end
end
