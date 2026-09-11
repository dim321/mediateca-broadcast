# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin sidebar groups", type: :system do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org, email: "ops@mediateca.test") }

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: operator.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  [
    [ "orders", "admin.nav.advertising_orders", :admin_tags_path ],
    [ "clients", "admin.nav.organizations", :admin_root_path ],
    [ "screen_fleet", "admin.nav.screens", :admin_root_path ],
    [ "media_library", "admin.nav.media_assets", :admin_root_path ],
    [ "directories", "admin.nav.business_spheres", :admin_root_path ]
  ].each do |group, link_key, path_helper|
    it "expands and collapses the #{group} group" do
      sign_in_through_ui
      visit public_send(path_helper)

      expect(page).not_to have_link(I18n.t(link_key), visible: true)

      find("[data-nav-group='#{group}'] summary").click
      expect(page).to have_link(I18n.t(link_key), visible: true)

      find("[data-nav-group='#{group}'] summary").click
      expect(page).not_to have_link(I18n.t(link_key), visible: true)
    end
  end
end
