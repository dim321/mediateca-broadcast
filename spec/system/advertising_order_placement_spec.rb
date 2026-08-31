# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advertising order placement", type: :system do
  let(:organization) { create(:organization, :client, name: "Triumph Org") }
  let(:user) { create(:user, :manager, organization: organization, email: "manager@triumph.test") }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization, name: "Витрины Триумф") }

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it "lets a manager create a draft grid and activate it" do
    asset
    group
    sign_in_through_ui

    click_link I18n.t("layouts.application.advertising_orders")
    click_link I18n.t("advertising_orders.index.new_order")

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-05")
    fill_in AdvertisingOrder.human_attribute_name(:product_name), with: "Triumph"
    select "1x1.png", from: "advertising_order_media_asset_id"
    select group.name, from: "advertising_order_lines_0_broadcast_point_group_id"
    fill_in "advertising_order_lines_0_price_per_day_rubles", with: "34020"
    find("input[data-date='2026-06-03']").set("36")
    find("input[data-date='2026-06-04']").set("36")
    find("input[data-date='2026-06-05']").set("36")
    click_button I18n.t("advertising_orders.form.submit")

    expect(page).to have_content(I18n.t("advertising_orders.create.created"))
    expect(page).to have_content("Triumph")

    click_button I18n.t("advertising_orders.show.activate")
    expect(page).to have_content(I18n.t("advertising_orders.activate.activated"))
    expect(AdvertisingOrder.last).to be_active
    expect(MediaPlan.active.count).to eq(1)
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
