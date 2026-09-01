# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Flowbite resource pages", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  it "renders remaining index pages with Flowbite chrome" do
    create(:station)
    create(:user, :manager)
    create(:screen_tag)
    create(:rotation)
    create(:rotation_item)
    create(:broadcast_point_group)
    create(:broadcast_point_group_membership)
    create(:play_log)

    [
      admin_stations_path,
      admin_users_path,
      admin_screen_tags_path,
      admin_rotations_path,
      admin_rotation_items_path,
      admin_broadcast_point_groups_path,
      admin_broadcast_point_group_memberships_path,
      admin_play_logs_path,
      admin_directory_business_spheres_path,
      admin_locations_path,
      admin_organizations_path,
      admin_advertising_orders_path
    ].each do |path|
      get path
      expect(response).to have_http_status(:success), "expected success for #{path}"
      expect(response.body).to include("/assets/admin-")
      expect(response.body).not_to include("app-container")
    end
  end

  it "renders new forms for remaining resources" do
    [
      new_admin_station_path,
      new_admin_user_path,
      new_admin_screen_tag_path,
      new_admin_rotation_path,
      new_admin_rotation_item_path,
      new_admin_broadcast_point_group_path,
      new_admin_broadcast_point_group_membership_path,
      new_admin_play_log_path,
      new_admin_directory_business_sphere_path,
      new_admin_location_path
    ].each do |path|
      get path
      expect(response).to have_http_status(:success), "expected success for #{path}"
    end
  end

  it "renders a profile show page" do
    organization = create(:organization, :client, :with_profile)

    get admin_profile_path(organization.profile)

    expect(response).to have_http_status(:success)
  end
end
