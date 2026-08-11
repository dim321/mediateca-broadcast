# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rotations::RotationItemComponent, type: :component do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:rotation) { create(:rotation, organization: organization) }

  it "renders broadcast, duration, media kind, content type and visibility without source" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: organization, uploaded_by: user,
                   content_type: "commercial", visibility: "network", duration_seconds: 42)
    item = create(:rotation_item, rotation: rotation, media_asset: asset)

    render_inline(described_class.new(rotation: rotation, item: item))

    expect(page).not_to have_content(I18n.t("media_assets.index.source_label"))
    expect(page).to have_link("source.ts")
    expect(page).to have_content("42s")
    expect(page).to have_content(I18n.t("media_assets.index.content_kinds.video"))
    expect(page).to have_content(I18n.t("media_assets.index.content_types.commercial"))
    expect(page).to have_content(I18n.t("media_assets.index.visibilities.network"))
    expect(page).to have_content(I18n.t("media_assets.index.columns.duration"))
    expect(page).to have_content(I18n.t("media_assets.index.columns.media_kind"))
    expect(page).to have_content(I18n.t("media_assets.index.columns.content_type"))
    expect(page).to have_content(I18n.t("media_assets.index.columns.visibility"))
  end
end
