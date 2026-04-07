# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Broadcast points management", type: :system do
  let(:user) { create(:user) }

  before do
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "creates a point with a new tag, filters by tag, and adds to a group" do
    create_broadcast_point_via_ui(name: "Shop 42", new_tag_names: "downtown")
    expect(page).to have_current_path(broadcast_points_path, ignore_query: true)
    expect(page).to have_content("Shop 42")
    expect(page).to have_content("downtown")

    downtown = Tag.find_by!(name: "downtown")
    check "tag_filter_#{downtown.id}"
    click_button I18n.t("broadcast_points.index.apply_filter")
    expect(page).to have_content("Shop 42")

    visit new_point_group_path
    fill_in "point_group_name", with: "Center screens"
    find("form[action*='point_groups'] input[type='submit']").click

    group = PointGroup.find_by!(name: "Center screens")
    visit point_group_path(group)
    check "add_point_#{BroadcastPoint.find_by!(name: 'Shop 42').id}"
    click_button I18n.t("point_groups.show.add_selected")
    expect(page).to have_content("Shop 42")
  end

  def create_broadcast_point_via_ui(name:, new_tag_names:)
    visit broadcast_points_path
    click_link I18n.t("broadcast_points.index.new_point")
    fill_in "broadcast_point_name", with: name
    fill_in "broadcast_point_new_tag_names", with: new_tag_names
    find("form[action*='broadcast_points'] input[type='submit']").click
  end
end
