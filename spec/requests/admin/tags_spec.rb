# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin tags", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client) { create(:organization, :client) }
  let(:client_user) { create(:user, :manager, organization: client) }

  describe "authentication" do
    it "redirects guests to login" do
      get admin_tags_path

      expect(response).to redirect_to(login_path)
    end

    it "denies client organization users" do
      sign_in_as(client_user)
      get admin_tags_path

      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in as operator" do
    before { sign_in_as(operator) }

    it "renders the Flowbite index, not Administrate chrome" do
      create(:tag, name: "Retail")

      get admin_tags_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Retail")
      expect(response.body).to include("/assets/admin-")
      expect(response.body).not_to include("app-container")
      expect(response.body).not_to include("navigation__link")
    end

    it "filters by name_cont and keeps the query in pagination links" do
      create(:tag, name: "Airport")
      26.times { |n| create(:tag, name: "Retail #{n}") }

      get admin_tags_path, params: { q: { name_cont: "Retail" }, page: 2 }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Airport")
      expect(response.body).to match(/q(%5B|\[)name_cont(%5D|\])=Retail/)
    end

    it "does not 500 on unknown ransack keys" do
      get admin_tags_path, params: { q: { unknown_field_eq: "nope" } }

      expect(response).to have_http_status(:success)
    end

    it "does not 500 when q is a scalar" do
      get admin_tags_path, params: { q: "notahash" }

      expect(response).to have_http_status(:success)
    end

    it "creates a tag and strips whitespace" do
      expect {
        post admin_tags_path, params: { tag: { name: "  Metro  " } }
      }.to change(Tag, :count).by(1)

      tag = Tag.find_by!(name: "Metro")
      expect(response).to redirect_to(admin_tag_path(tag))
    end

    it "rejects a duplicate name case-insensitively with 422" do
      create(:tag, name: "Retail")

      expect {
        post admin_tags_path, params: { tag: { name: "retail" } }
      }.not_to change(Tag, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates a tag name" do
      tag = create(:tag, name: "Retail")

      patch admin_tag_path(tag), params: { tag: { name: "Airport" } }

      expect(response).to redirect_to(admin_tag_path(tag))
      expect(tag.reload.name).to eq("Airport")
    end

    it "returns 404 for an unknown id" do
      get admin_tag_path(0)

      expect(response).to have_http_status(:not_found)
    end

    it "renders the Flowbite screens index" do
      get admin_screens_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("/assets/admin-")
      expect(response.body).not_to include("app-container")
      expect(response.body).not_to include("navigation__link")
    end

    it "destroys a tag and its screen_tags" do
      tag = create(:tag, name: "Retail")
      screen_tag = create(:screen_tag, tag: tag)

      expect {
        delete admin_tag_path(tag)
      }.to change(Tag, :count).by(-1)

      expect(ScreenTag.where(id: screen_tag.id)).to be_empty
      expect(response).to redirect_to(admin_tags_path)
    end
  end
end
