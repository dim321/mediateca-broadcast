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
end
