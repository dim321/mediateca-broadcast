# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Playlist reorder UI", type: :system do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, organization: user.organization) }
  let!(:item_one) { create(:playlist_item, playlist: playlist, position: 1) }
  let!(:item_two) { create(:playlist_item, playlist: playlist, position: 2) }

  before do
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "renders a sortable list wired to the internal reorder endpoint" do
    visit playlist_path(playlist)

    expect(page).to have_css('[data-controller~="playlist-sort"]')
    expect(page).to have_css("ul[data-playlist-sort-target='list']")
    expect(page).to have_css("li[data-item-id=\"#{item_one.id}\"]")
    expect(page).to have_css("li[data-item-id=\"#{item_two.id}\"]")

    reorder_url = internal_playlist_reorder_path(playlist_id: playlist.id)
    expect(page.html).to include(reorder_url)
  end
end
