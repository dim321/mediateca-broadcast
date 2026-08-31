# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin business spheres", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client) { create(:organization, :client) }
  let(:client_user) { create(:user, :manager, organization: client) }

  describe "authentication" do
    it "denies client organization users" do
      sign_in_as(client_user)
      get admin_directory_business_spheres_path

      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in as operator" do
    before { sign_in_as(operator) }

    it "lists spheres and creates a new value" do
      create(:directory_business_sphere, name: "Ритейл")

      get admin_directory_business_spheres_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Ритейл")

      expect {
        post admin_directory_business_spheres_path, params: {
          directory_business_sphere: { name: "СМИ, Полиграфия, Рекламное Агентство" }
        }
      }.to change(Directory::BusinessSphere, :count).by(1)

      sphere = Directory::BusinessSphere.find_by!(name: "СМИ, Полиграфия, Рекламное Агентство")
      expect(response).to redirect_to(admin_directory_business_sphere_path(sphere))
    end

    it "updates a sphere name" do
      sphere = create(:directory_business_sphere, name: "Ритейл")

      patch admin_directory_business_sphere_path(sphere), params: {
        directory_business_sphere: { name: "Розничная торговля" }
      }

      expect(response).to redirect_to(admin_directory_business_sphere_path(sphere))
      expect(sphere.reload.name).to eq("Розничная торговля")
    end

    it "destroys an unused sphere" do
      sphere = create(:directory_business_sphere, name: "СМИ")

      expect {
        delete admin_directory_business_sphere_path(sphere)
      }.to change(Directory::BusinessSphere, :count).by(-1)

      expect(response).to redirect_to(admin_directory_business_spheres_path)
    end

    it "refuses to destroy a sphere used by a profile" do
      sphere = create(:directory_business_sphere, name: "Ритейл")
      create(:profile, organization: client, business_sphere: sphere)

      expect {
        delete admin_directory_business_sphere_path(sphere)
      }.not_to change(Directory::BusinessSphere, :count)

      expect(response).to redirect_to(admin_directory_business_spheres_path)
      expect(flash[:alert]).to eq(I18n.t("admin.business_spheres.destroy_restricted"))
      expect(sphere.reload).to be_persisted
    end
  end
end
