# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin sidebar", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  def nav_group(key)
    Nokogiri::HTML(response.body).at_css("[data-nav-group='#{key}']")
  end

  it "renders the orders group with advertising orders and media plans" do
    get admin_root_path

    group = nav_group("orders")
    expect(group).to be_present
    expect(group.text).to include(
      I18n.t("admin.nav.groups.orders"),
      I18n.t("admin.nav.advertising_orders"),
      I18n.t("admin.nav.media_plans")
    )
    expect(group.css("a").map { |link| link["href"] }).to eq(
      [ admin_advertising_orders_path, admin_media_plans_path ]
    )
  end

  it "renders the clients group with organizations and users" do
    get admin_root_path

    group = nav_group("clients")
    expect(group).to be_present
    expect(group.css("a").map { |link| link["href"] }).to eq(
      [ admin_organizations_path, admin_users_path ]
    )
  end

  it "renders the screen fleet group with fleet resources" do
    get admin_root_path

    group = nav_group("screen_fleet")
    expect(group).to be_present
    expect(group.css("a").map { |link| link["href"] }).to eq(
      [
        admin_locations_path,
        admin_stations_path,
        admin_screens_path,
        admin_broadcast_point_groups_path,
        admin_screen_tags_path,
        admin_broadcast_point_group_memberships_path
      ]
    )
  end

  it "renders the media library group with media assets and rotations" do
    get admin_root_path

    group = nav_group("media_library")
    expect(group).to be_present
    expect(group.text).to include(
      I18n.t("admin.nav.groups.media_library"),
      I18n.t("admin.nav.media_assets"),
      I18n.t("admin.nav.rotations"),
      I18n.t("admin.nav.rotation_items")
    )
    expect(group.css("a").map { |link| link["href"] }).to eq(
      [ admin_media_assets_path, admin_rotations_path, admin_rotation_items_path ]
    )
  end

  it "renders the directories group with business spheres and tags" do
    get admin_root_path

    group = nav_group("directories")
    expect(group.css("a").map { |link| link["href"] }).to eq(
      [ admin_directory_business_spheres_path, admin_tags_path ]
    )
  end

  it "expands the orders group on the admin root and keeps other groups collapsed" do
    get admin_root_path

    expect(nav_group("orders").at_css("details")["open"]).to eq("open")
    %w[clients screen_fleet media_library directories].each do |key|
      details = nav_group(key).at_css("details")
      expect(details).to be_present
      expect(details["open"]).to be_nil
    end
  end

  it "expands a named group when a child page is current" do
    get admin_organizations_path

    expect(nav_group("clients").at_css("details")["open"]).to eq("open")
    expect(nav_group("orders").at_css("details")["open"]).to be_nil
    expect(nav_group("screen_fleet").at_css("details")["open"]).to be_nil
    expect(nav_group("media_library").at_css("details")["open"]).to be_nil
    expect(nav_group("directories").at_css("details")["open"]).to be_nil
  end
end
