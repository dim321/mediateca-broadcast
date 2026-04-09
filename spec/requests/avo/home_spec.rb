# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avo::Home", type: :request do
  let(:user) { create(:user) }

  describe "GET /avo" do
    it "открывает дашборд для авторизованного пользователя кабинета" do
      sign_in_as(user)

      expect { get "/avo" }.not_to raise_error
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/avo")
    end
  end
end
