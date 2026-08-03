# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rotation reorder UI", type: :system do
  let(:user) { create(:user) }
  let(:rotation) { create(:rotation, organization: user.organization) }
  let!(:item_one) { create(:rotation_item, rotation: rotation, position: 1) }
  let!(:item_two) { create(:rotation_item, rotation: rotation, position: 2) }

  before do
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "renders a sortable list wired to the internal reorder endpoint" do
    visit rotation_path(rotation)

    expect(page).to have_css('[data-controller~="rotation-sort"]')
    expect(page).to have_css("ul[data-rotation-sort-target='list']")
    expect(page).to have_css("li[data-item-id=\"#{item_one.id}\"]")
    expect(page).to have_css("li[data-item-id=\"#{item_two.id}\"]")

    reorder_url = internal_rotation_reorder_path(rotation_id: rotation.id)
    expect(page.html).to include(reorder_url)
  end
end
