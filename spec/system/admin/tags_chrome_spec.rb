# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin chrome isolation", type: :system do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org, email: "ops@mediateca.test") }

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: operator.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "loads admin.css on tags and Administrate styles on screens" do
    create(:tag, name: "Retail")
    sign_in_through_ui

    visit admin_tags_path
    expect(page).to have_content("Retail")
    expect(page.html).to include("/assets/admin-")
    expect(page.html).not_to include("administrate")

    click_link I18n.t("admin.nav.screens")
    expect(page).to have_css(".navigation")
    expect(page.html).not_to match(%r{rel="stylesheet"[^>]+/assets/admin-})

    visit root_path
    expect(page.html).to include("tailwind")
    expect(page.html).not_to match(%r{rel="stylesheet"[^>]+/assets/admin-})
  end
end
