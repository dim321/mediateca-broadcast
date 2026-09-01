# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switching", type: :request do
  context "when signed in as a cabinet user" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "defaults to Russian" do
      get media_assets_path
      expect(response.body).to include(I18n.t("layouts.application.media_library", locale: :ru))
      expect(response.body).to include('lang="ru"')
    end

    it "switches to English and keeps the choice" do
      patch locale_path(locale: :en), headers: { "HTTP_REFERER" => media_assets_url }
      expect(response).to redirect_to(media_assets_path)

      follow_redirect!
      expect(response.body).to include(I18n.t("layouts.application.media_library", locale: :en))
      expect(response.body).to include('lang="en"')
    end

    it "ignores unsupported locales" do
      patch locale_path(locale: :de)
      get media_assets_path
      expect(response.body).to include('lang="ru"')
    end
  end

  context "when signed in as an operator" do
    let(:operator) { create(:user, :manager, organization: create(:organization, :operator)) }

    before { sign_in_as(operator) }

    it "renders the locale switcher in the navbar, not the sidebar" do
      get admin_media_plans_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("nav form[action*='locale']")).to be_present
      expect(page.at_css("aside form[action*='locale']")).to be_nil
    end

    it "switches locale and returns to the admin page" do
      patch locale_path(locale: :en), headers: { "HTTP_REFERER" => admin_media_plans_url }
      expect(response).to redirect_to(admin_media_plans_path)

      follow_redirect!
      expect(response.body).to include('lang="en"')
    end
  end
end
