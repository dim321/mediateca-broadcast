# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cabinet shell", type: :system do
  let(:organization) { create(:organization, name: "Acme Screens") }
  let(:user) { create(:user, organization: organization, email: "manager@acme.test") }

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "shows the organization and highlights the active nav section" do
    sign_in_through_ui

    expect(page).to have_content("Acme Screens")
    expect(page).to have_content(I18n.t("layouts.application.brand"))
    expect(page).to have_css("a.menu-active", text: I18n.t("layouts.application.media_library"))

    click_link I18n.t("layouts.application.rotations")
    expect(page).to have_content(I18n.t("rotations.index.title"))
    expect(page).to have_css("a.menu-active", text: I18n.t("layouts.application.rotations"))

    click_link I18n.t("layouts.application.broadcast_point_groups")
    expect(page).to have_content(I18n.t("broadcast_point_groups.index.title"))
    expect(page).to have_css("a.menu-active", text: I18n.t("layouts.application.broadcast_point_groups"))

    click_link I18n.t("layouts.application.media_plans")
    expect(page).to have_content(I18n.t("media_plans.index.title"))
    expect(page).to have_css("a.menu-active", text: I18n.t("layouts.application.media_plans"))
  end

  it "renders login without the cabinet sidebar" do
    visit login_path

    expect(page).to have_content(I18n.t("sessions.new.title"))
    expect(page).not_to have_css(".drawer-side")
    expect(page).not_to have_link(I18n.t("layouts.application.rotations"))
  end
end
