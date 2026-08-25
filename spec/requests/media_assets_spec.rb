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
      expect(row.name).to eq("tr")
      expect(row["id"]).to eq(card_id)
      expect(row.text).to include("source.mp4")
      expect(row.text).to include("source.ts")
    end
  end
end
