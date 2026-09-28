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

  it "renders the show page for an asset with attachments" do
    media_asset = create(:media_asset, :with_png_file, :ready, organization: client_org)

    get admin_media_asset_path(media_asset)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("1x1.png")
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
