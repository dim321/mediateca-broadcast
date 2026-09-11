# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin users", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client_org) { create(:organization, :client) }

  before { sign_in_as(operator) }

  it "creates a user with profile fields and status" do
    expect {
      post admin_users_path, params: {
        user: {
          email: "new.manager@example.com",
          organization_id: client_org.id,
          role: "manager",
          status: "active",
          first_name: "Petr",
          last_name: "Sidorov",
          phone: "+79990001122",
          job_title: "Client manager",
          telegram: "@petr",
          location: "Kazan",
          password: "password123456",
          password_confirmation: "password123456"
        }
      }
    }.to change(User, :count).by(1)

    user = User.find_by!(email: "new.manager@example.com")
    expect(response).to redirect_to(admin_user_path(user))
    expect(user).to have_attributes(
      first_name: "Petr",
      last_name: "Sidorov",
      phone: "+79990001122",
      job_title: "Client manager",
      telegram: "@petr",
      location: "Kazan",
      status: "active"
    )
  end

  it "updates profile fields and status" do
    user = create(:user, organization: client_org, email: "edit.me@example.com")

    patch admin_user_path(user), params: {
      user: {
        email: user.email,
        organization_id: client_org.id,
        role: "accountant",
        status: "blocked",
        first_name: "Olga",
        last_name: "Smirnova",
        phone: "+71112223344",
        job_title: "Accountant",
        telegram: "@olga",
        location: "Sochi"
      }
    }

    expect(response).to redirect_to(admin_user_path(user))
    expect(user.reload).to have_attributes(
      first_name: "Olga",
      last_name: "Smirnova",
      phone: "+71112223344",
      job_title: "Accountant",
      telegram: "@olga",
      location: "Sochi",
      role: "accountant",
      status: "blocked"
    )
  end

  it "renders the profile-like show page" do
    user = create(:user, :with_profile, organization: client_org)

    get admin_user_path(user)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(user.display_name)
    expect(response.body).to include(user.phone)
    expect(response.body).to include(I18n.t("enums.user.status.active"))
  end
end
