# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin organizations profile", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:sphere) { create(:directory_business_sphere, name: "Ритейл") }

  before { sign_in_as(operator) }

  it "shows nested profile fields on the new organization form" do
    get new_admin_organization_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('name="organization[profile_attributes][brand]"')
    expect(response.body).to include('name="organization[profile_attributes][holding]"')
    expect(response.body).to include("organization[profile_attributes][business_sphere_id]")
  end

  it "creates an organization with a profile chosen from the directory" do
    expect {
      post admin_organizations_path, params: {
        organization: {
          name: "Триумф",
          kind: "client",
          time_zone: "Asia/Krasnoyarsk",
          profile_attributes: {
            brand: "Triumph",
            holding: "Командор",
            business_sphere_id: sphere.id
          }
        }
      }
    }.to change(Organization, :count).by(1).and change(Profile, :count).by(1)

    organization = Organization.find_by!(name: "Триумф")
    expect(response).to redirect_to(admin_organization_path(organization))
    expect(organization.profile.brand).to eq("Triumph")
    expect(organization.profile.holding).to eq("Командор")
    expect(organization.profile.business_sphere).to eq(sphere)
  end

  it "updates an existing organization profile including the business sphere" do
    organization = create(:organization, :client, :with_profile, name: "Аллея")
    other_sphere = create(:directory_business_sphere, name: "СМИ")

    patch admin_organization_path(organization), params: {
      organization: {
        name: "Аллея",
        kind: "client",
        time_zone: organization.time_zone,
        profile_attributes: {
          id: organization.profile.id,
          brand: "Аллея",
          holding: "Командор",
          business_sphere_id: other_sphere.id
        }
      }
    }

    expect(response).to redirect_to(admin_organization_path(organization))
    expect(organization.profile.reload.brand).to eq("Аллея")
    expect(organization.profile.holding).to eq("Командор")
    expect(organization.profile.business_sphere).to eq(other_sphere)
  end

  it "shows the profile on the organization page" do
    organization = create(
      :organization,
      :client,
      :with_profile,
      name: "Триумф",
      profile_brand: "Triumph",
      profile_holding: "Командор",
      profile_business_sphere: sphere
    )

    get admin_organization_path(organization)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Triumph")
    expect(response.body).to include("Командор")
    expect(response.body).to include("Ритейл")
  end
end
