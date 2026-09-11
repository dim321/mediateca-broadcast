# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts", type: :request do
  let(:user) { create(:user, :with_profile, password: "password123456") }

  before { sign_in_as(user) }

  it "updates the signed-in user's profile fields" do
    patch account_path, params: {
      user: {
        first_name: "Nikolay",
        last_name: "Orlov",
        phone: "+70001112233",
        job_title: "Director",
        telegram: "@nik",
        location: "Tula"
      }
    }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(account_path)
    expect(user.reload).to have_attributes(
      first_name: "Nikolay",
      last_name: "Orlov",
      phone: "+70001112233",
      job_title: "Director",
      telegram: "@nik",
      location: "Tula"
    )
  end

  it "does not allow changing email, role, organization, or status from the cabinet" do
    other_org = create(:organization, :client)
    original_email = user.email
    original_org_id = user.organization_id

    patch account_path, params: {
      user: {
        first_name: "Safe",
        last_name: "Update",
        email: "hacker@example.com",
        role: "administrator",
        organization_id: other_org.id,
        status: "blocked"
      }
    }

    expect(response).to have_http_status(:see_other)
    user.reload
    expect(user.email).to eq(original_email)
    expect(user.role).to eq("manager")
    expect(user.organization_id).to eq(original_org_id)
    expect(user.status).to eq("active")
    expect(user.first_name).to eq("Safe")
    expect(user.last_name).to eq("Update")
  end

  it "renders the account form for the current user" do
    get account_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include(I18n.t("accounts.show.title"))
    expect(response.body).to include(user.first_name)
  end
end
