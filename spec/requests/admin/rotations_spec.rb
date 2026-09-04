# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin rotations", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  it "hides system-managed theme rotations from the ordinary index" do
    ordinary = create(:rotation, name: "Client catalog", organization: operator_org)
    theme = create(:service_theme, organization: operator_org, name: "Salon")
    hidden = theme.welcome_rotation
    hidden.update!(name: "Salon · welcome")

    get admin_rotations_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(ordinary.name)
    expect(response.body).not_to include(hidden.name)
  end
end
