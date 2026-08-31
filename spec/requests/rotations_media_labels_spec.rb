# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rotation media labels", type: :request do
  let(:user) { create(:user) }
  let(:rotation) { create(:rotation, organization: user.organization) }

  before { sign_in_as(user) }

  it "shows broadcast link and media attributes for rotation items" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user,
                   content_type: "own", visibility: "organization", duration_seconds: 15)
    create(:rotation_item, rotation: rotation, media_asset: asset)

    get rotation_path(rotation)

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(I18n.t("media_assets.index.source_label"))
    expect(response.body).to include("source.ts")
    expect(response.body).to include("15s")
    expect(response.body).to include(I18n.t("media_assets.index.content_kinds.video"))
    expect(response.body).to include(I18n.t("media_assets.index.content_types.own"))
    expect(response.body).to include(I18n.t("media_assets.index.visibilities.organization"))
  end

  it "uses combined labels in the add-media select" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user)

    get rotation_path(rotation)

    expect(response.body).to include("source.mp4 · source.ts")
  end
end
