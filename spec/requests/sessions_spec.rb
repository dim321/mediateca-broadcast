# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "POST /login" do
    it "redirects a client user to the cabinet media library" do
      user = create(:user, password: "password123456")

      post login_path, params: { email: user.email, password: "password123456" }

      expect(response).to redirect_to(media_assets_path)
    end

    it "redirects an operator user to the admin panel" do
      operator = create(:user, organization: create(:organization, :operator), password: "password123456")

      post login_path, params: { email: operator.email, password: "password123456" }

      expect(response).to redirect_to(admin_root_path)
    end

    it "rejects invalid credentials" do
      user = create(:user, password: "password123456")

      post login_path, params: { email: user.email, password: "wrong-password" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /login" do
    it "redirects a signed-in client to the cabinet" do
      user = create(:user)
      sign_in_as(user)

      get login_path

      expect(response).to redirect_to(media_assets_path)
    end

    it "redirects a signed-in operator to the admin panel" do
      operator = create(:user, organization: create(:organization, :operator))
      sign_in_as(operator)

      get login_path

      expect(response).to redirect_to(admin_root_path)
    end
  end
end
