# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rotation media labels", type: :request do
  let(:user) { create(:user) }
  let(:rotation) { create(:rotation, organization: user.organization) }

  before { sign_in_as(user) }

  it "shows source and broadcast links for rotation items" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user)
    create(:rotation_item, rotation: rotation, media_asset: asset)

    get rotation_path(rotation)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("source.mp4")
    expect(response.body).to include("source.ts")
  end

  it "uses combined labels in the add-media select" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user)

    get rotation_path(rotation)

    expect(response.body).to include("source.mp4 · source.ts")
  end
end
