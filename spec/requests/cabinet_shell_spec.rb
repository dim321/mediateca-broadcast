# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cabinet shell", type: :request do
  let(:organization) { create(:organization, name: "Acme Screens") }
  let(:user) { create(:user, organization: organization) }

  it "shows tenant context and nav for signed-in users" do
    sign_in_as(user)
    get root_path

    expect(response.body).to include("Acme Screens")
    expect(response.body).to include(I18n.t("layouts.application.media_library"))
    expect(response.body).to include(I18n.t("layouts.application.rotations"))
    expect(response.body).to include(I18n.t("layouts.application.broadcast_point_groups"))
    expect(response.body).to include(I18n.t("layouts.application.media_plans"))
    expect(response.body).not_to include(I18n.t("layouts.application.airtime_bookings"))
    expect(response.body).to include(I18n.t("layouts.application.fleet_screens"))
    expect(response.body).to include("menu-active")
  end

  it "does not render cabinet sidebar on login" do
    get login_path

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include("drawer-side")
    expect(response.body).not_to include(I18n.t("layouts.application.media_library"))
  end
end
