# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advertising order placement", type: :system do
  let(:organization) { create(:organization, :client, name: "Triumph Org") }
  let(:user) { create(:user, :manager, organization: organization, email: "manager@triumph.test") }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization, name: "Витрины Триумф") }

  def named_screen
    group.screens.first.tap do |screen|
      screen.update!(name: "Витрина Триумф")
      screen.location.update!(name: "ТЦ Галерея")
      screen.station.update!(name: "Станция Невидимая")
      portrait = screen.broadcast_portrait
      if portrait
        freqs = Array(portrait.block_frequencies_per_hour)
        portrait.update!(block_frequencies_per_hour: (freqs | [ 3 ]).sort) unless freqs.include?(3)
      else
        create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
      end
    end
  end

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it "lets a manager create a draft grid and activate it", :js do
    asset
    screen = named_screen
    sign_in_through_ui

    click_link I18n.t("layouts.application.advertising_orders")
    click_link I18n.t("advertising_orders.index.new_order")

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-05")
    fill_in AdvertisingOrder.human_attribute_name(:product_name), with: "Triumph"
    select "1x1.png", from: "advertising_order_media_asset_id"
    check "order_screen_#{screen.id}"
    select "3", from: "advertising_order_shows_per_hour"
    expect(page).not_to have_field("advertising_order_lines_0_broadcast_point_group_id")
    expect(page).not_to have_field("advertising_order_lines_0_price_per_day_rubles")
    click_button I18n.t("advertising_orders.form.submit")

    expect(page).to have_content(I18n.t("advertising_orders.create.created"))
    expect(page).to have_content("Triumph")

    click_link I18n.t("advertising_orders.show.edit")
    within("[data-order-grid-target='lineRow']") do
      expect(page).to have_content("Витрина Триумф")
      expect(page).to have_content("ТЦ Галерея")
      expect(page).not_to have_content("Станция Невидимая")
      total_shows = AdvertisingOrder.last.advertising_order_lines.sole.total_shows
      expect(find("[data-order-grid-target='total']").value).to eq(total_shows.to_s)
    end
    expect(find("[data-order-grid-target='grandTotal']").value).to eq(AdvertisingOrder.last.total_shows.to_s)

    visit advertising_order_path(AdvertisingOrder.last)
    click_button I18n.t("advertising_orders.show.activate")
    expect(page).to have_content(I18n.t("advertising_orders.activate.activated"))
    expect(AdvertisingOrder.last).to be_active
    expect(MediaPlan.active.count).to be >= 1
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
