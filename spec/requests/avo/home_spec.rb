# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avo::Home", type: :request do
  describe "GET /avo" do
    it "opens the dashboard for an operator user" do
      user = create(:user, organization: create(:organization, :operator))
      sign_in_as(user)

      expect { get "/avo" }.not_to raise_error
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/avo")
    end

    it "denies access to client users" do
      user = create(:user, organization: create(:organization, :client))
      sign_in_as(user)

      get "/avo"

      expect(response).to redirect_to('/')
    end
  end
end
