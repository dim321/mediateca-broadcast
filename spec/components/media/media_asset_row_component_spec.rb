# frozen_string_literal: true

require "rails_helper"

RSpec.describe Media::MediaAssetRowComponent, type: :component do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  it "renders source and broadcast links for a ready video" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: organization, uploaded_by: user,
                   content_type: "own", visibility: "organization", duration_seconds: 12)

    render_inline(described_class.new(media_asset: asset))

    expect(page).to have_css("tr##{ActionView::RecordIdentifier.dom_id(asset, :card)}")
    expect(page).to have_link("source.mp4")
    expect(page).to have_link("source.ts")
    expect(page).to have_content("Ready")
    expect(page).to have_content("12s")
    expect(page).to have_content(I18n.t("media_assets.index.content_types.own"))
    expect(page).to have_content(I18n.t("media_assets.index.visibilities.organization"))
  end

  it "renders N/A broadcast cell for an image" do
    asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
    render_inline(described_class.new(media_asset: asset))
    expect(page).to have_content(I18n.t("media_assets.index.broadcast_na"))
    expect(page).not_to have_link(href: /broadcast/)
  end
end
