# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin service themes", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client) { create(:organization, :client) }
  let(:client_user) { create(:user, :manager, organization: client) }

  describe "authentication" do
    it "redirects guests to login" do
      get admin_service_themes_path

      expect(response).to redirect_to(login_path)
    end

    it "denies client organization users" do
      sign_in_as(client_user)
      get admin_service_themes_path

      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in as operator" do
    before { sign_in_as(operator) }

    it "renders the Flowbite index, not daisyUI chrome" do
      create(:service_theme, organization: operator_org, name: "Салон красоты")

      get admin_service_themes_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Салон красоты")
      expect(response.body).to include("/assets/admin-")
      expect(response.body).to include(I18n.t("admin.nav.groups.service_library"))
      expect(response.body).not_to include("app-container")
      expect(response.body).not_to include('class="btn')
    end

    it "creates a theme with four empty system-managed rotations (AE1)" do
      expect {
        post admin_service_themes_path, params: { service_theme: { name: "  Салон красоты  " } }
      }.to change(ServiceTheme, :count).by(1)
        .and change(Rotation, :count).by(4)

      theme = ServiceTheme.find_by!(name: "Салон красоты")
      expect(response).to redirect_to(admin_service_theme_path(theme))
      expect(theme.organization).to eq(operator_org)
      expect(theme.rotations).to all(be_system_managed)
      expect(theme.rotations.map { |rotation| rotation.rotation_items.count }).to all(eq(0))
    end

    it "rejects a duplicate name with 422" do
      create(:service_theme, organization: operator_org, name: "Салон красоты")

      expect {
        post admin_service_themes_path, params: { service_theme: { name: "Салон красоты" } }
      }.not_to change(ServiceTheme, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "shows four folders on the theme" do
      theme = ServiceThemes::Create.call(organization: operator_org, name: "Рыбный отдел")

      get admin_service_theme_path(theme)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Рыбный отдел")
      expect(response.body).to include(I18n.t("enums.broadcast_portrait_block.kind.service_header_start"))
      expect(response.body).to include(I18n.t("enums.broadcast_portrait_block.kind.service_welcome"))
      expect(response.body).to include(I18n.t("enums.broadcast_portrait_block.kind.service_close"))
    end

    it "updates a theme name" do
      theme = create(:service_theme, organization: operator_org, name: "Салон")

      patch admin_service_theme_path(theme), params: { service_theme: { name: "  Рыбный отдел  " } }

      expect(response).to redirect_to(admin_service_theme_path(theme))
      expect(theme.reload.name).to eq("Рыбный отдел")
    end

    it "destroys an unused theme and its rotations" do
      theme = ServiceThemes::Create.call(organization: operator_org, name: "Салон")
      rotation_ids = theme.rotations.map(&:id)

      expect {
        delete admin_service_theme_path(theme)
      }.to change(ServiceTheme, :count).by(-1)

      expect(Rotation.where(id: rotation_ids)).to be_empty
      expect(response).to redirect_to(admin_service_themes_path)
    end

    it "restricts destroy when a portrait uses the theme (AE8)" do
      theme = create(:service_theme, organization: operator_org)
      create(:broadcast_portrait, :for_screen, service_theme: theme)

      expect {
        delete admin_service_theme_path(theme)
      }.not_to change(ServiceTheme, :count)

      expect(response).to redirect_to(admin_service_themes_path)
      expect(flash[:alert]).to eq(I18n.t("admin.service_themes.destroy_restricted"))
      expect(theme.reload).to be_persisted
    end

    it "does not 500 when q is a scalar" do
      get admin_service_themes_path, params: { q: "notahash" }

      expect(response).to have_http_status(:success)
    end
  end
end
