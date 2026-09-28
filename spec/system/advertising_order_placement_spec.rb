# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advertising order placement", type: :system do
  let(:organization) { create(:organization, :client, name: "Triumph Org") }
  let(:user) { create(:user, :manager, organization: organization, email: "manager@triumph.test") }
  let(:traffic_manager) { create(:user, :traffic_manager, organization: organization, email: "traffic@triumph.test") }
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

  def order_window_value(row, target)
    row.find("[data-order-windows-target='#{target}']", visible: :all).value
  end

  def set_order_window(row, target, value)
    which = target == "startsAt" ? "start" : "end"
    hour, minute = value.split(":")
    row.find("[data-order-windows-part='#{which}-hour']").select(hour)
    row.find("[data-order-windows-part='#{which}-minute']").select(minute)
  end

  def sign_in_through_ui(account = user)
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: account.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "activates a prepared draft order without JavaScript" do
    asset
    screen = named_screen
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Triumph"
    )
    fill_order_grid!(order, screen: screen, dates: [ Date.new(2026, 6, 3) ])
    MediaAssets::MarkContentValidated.call(media_asset: asset, user: traffic_manager)
    sign_in_through_ui(traffic_manager)

    visit advertising_order_path(order)
    click_button I18n.t("advertising_orders.show.activate")

    expect(page).to have_content(I18n.t("advertising_orders.activate.activated"))
    expect(order.reload).to be_active
    expect(MediaPlan.active.count).to be >= 1
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it "lets a manager create a draft grid and activate it", :js do
    asset
    screen = named_screen
    sign_in_through_ui

    click_link I18n.t("layouts.application.advertising_orders")
    click_link I18n.t("advertising_orders.index.new_order")

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-05")
    select "1x1.png (10s)", from: "advertising_order_available_media_asset"
    click_button I18n.t("advertising_orders.form.add_clip")
    check "order_screen_#{screen.id}"
    click_button I18n.t("advertising_orders.form.submit")
    expect(page).to have_content(AdvertisingOrder.human_attribute_name(:product_name))
    fill_in AdvertisingOrder.human_attribute_name(:product_name), with: "Triumph"
    select "3", from: "advertising_order_shows_per_hour"
    expect(page).not_to have_field("advertising_order_lines_0_broadcast_point_group_id")
    expect(page).not_to have_field("advertising_order_lines_0_price_per_day_rubles")
    click_button I18n.t("advertising_orders.form.submit")

    expect(page).to have_content(I18n.t("advertising_orders.create.created", name: "Triumph"))
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
    expect(page).to have_button(I18n.t("advertising_orders.show.activate"), disabled: true)

    click_button I18n.t("layouts.application.sign_out")
    MediaAssets::MarkContentValidated.call(media_asset: asset, user: traffic_manager)
    sign_in_through_ui(traffic_manager)
    visit advertising_order_path(AdvertisingOrder.last)
    click_button I18n.t("advertising_orders.show.activate")
    expect(page).to have_content(I18n.t("advertising_orders.activate.activated"))
    expect(AdvertisingOrder.last).to be_active
    expect(MediaPlan.active.count).to be >= 1
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  it "fills day cells from shows_per_hour × window ∩ open hours after screen selection", :js do
    asset
    screen = named_screen
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-03")
    check "order_screen_#{screen.id}"
    expect(page).to have_select("advertising_order_shows_per_hour", disabled: false)
    select "3", from: "advertising_order_shows_per_hour"

    within("[data-order-grid-target='lineRow']") do
      # automatic window matches screen hours 09:00–21:00; 12 open hours × 3 shows = 36
      expect(find("[data-order-grid-target='cell']").value).to eq("36")
      expect(find("[data-order-grid-target='total']").value).to eq("36")
    end
    expect(find("[data-order-grid-target='grandTotal']").value).to eq("36")
  end

  it "sets the automatic window to the earliest start and latest end of selected screens", :js do
    asset
    first_screen = named_screen
    second_screen = create(:screen, station: first_screen.station).tap do |screen|
      hours = Location::OperatingHours::DAY_KEYS.index_with do
        [ { "start" => "10:00", "end" => "20:00" } ]
      end
      screen.update!(inherit_operating_hours_from_location: false, operating_hours: hours)
    end
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-03")
    check "order_screen_#{first_screen.id}"
    check "order_screen_#{second_screen.id}"

    row = find("[data-order-windows-target='row']")
    expect(order_window_value(row, "startsAt")).to eq("09:00")
    expect(order_window_value(row, "endsAt")).to eq("21:00")
    expect(row.find("[data-order-windows-part='start-hour']").value).to eq("09")
    expect(row.find("[data-order-windows-part='end-hour']").value).to eq("21")
  end

  it "preserves manually edited and added windows when screens change", :js do
    asset
    first_screen = named_screen
    second_screen = create(:screen, station: first_screen.station)
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-03")
    check "order_screen_#{first_screen.id}"

    first_row = find("[data-order-windows-target='row']")
    set_order_window(first_row, "startsAt", "11:00")
    set_order_window(first_row, "endsAt", "12:00")
    click_button I18n.t("advertising_orders.form.add_window")

    rows = all("[data-order-windows-target='row']")
    set_order_window(rows.last, "startsAt", "14:00")
    set_order_window(rows.last, "endsAt", "15:00")
    check "order_screen_#{second_screen.id}"

    expect(order_window_value(rows.first, "startsAt")).to eq("11:00")
    expect(order_window_value(rows.first, "endsAt")).to eq("12:00")
    expect(order_window_value(rows.last, "startsAt")).to eq("14:00")
    expect(order_window_value(rows.last, "endsAt")).to eq("15:00")
  end

  it "recomputes day cells when windows are added and the default window is removed", :js do
    asset
    screen = named_screen
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-03")
    check "order_screen_#{screen.id}"
    expect(page).to have_select("advertising_order_shows_per_hour", disabled: false)
    select "4", from: "advertising_order_shows_per_hour"

    within("[data-order-grid-target='lineRow']") do
      expect(find("[data-order-grid-target='cell']").value).to eq("48")
    end

    click_button I18n.t("advertising_orders.form.add_window")
    within("[data-order-windows-target='list']") do
      first("button", text: I18n.t("advertising_orders.form.remove_window")).click
    end

    within("[data-order-grid-target='lineRow']") do
      # remaining template window 09:00–12:00 ∩ open hours → 3 hours × 4 shows = 12
      expect(find("[data-order-grid-target='cell']").value).to eq("12")
      expect(find("[data-order-grid-target='total']").value).to eq("12")
    end
    expect(find("[data-order-grid-target='grandTotal']").value).to eq("12")
  end

  it "lets a manager add multiple clips before creating a draft", :js do
    first_clip = asset
    second_clip = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12)
    second_clip.file.blob.update!(filename: "triumph-b.png")
    screen = named_screen
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-06-03", grid_to: "2026-06-03")
    select "1x1.png (10s)", from: "advertising_order_available_media_asset"
    click_button I18n.t("advertising_orders.form.add_clip")
    select "triumph-b.png (12s)", from: "advertising_order_available_media_asset"
    click_button I18n.t("advertising_orders.form.add_clip")
    check "order_screen_#{screen.id}"
    fill_in AdvertisingOrder.human_attribute_name(:product_name), with: "Triumph Duo"
    select "3", from: "advertising_order_shows_per_hour"
    click_button I18n.t("advertising_orders.form.submit")

    expect(page).to have_content(I18n.t("advertising_orders.create.created", name: "Triumph Duo"))
    order = AdvertisingOrder.last
    expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ first_clip, second_clip ])
  end

  it "splits chess distribution independently inside each month", :js do
    asset
    first_screen = named_screen
    second_screen = create(:screen, station: first_screen.station, name: "Витрина 2")
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: second_screen)
    create(:broadcast_portrait, :for_screen, screen: second_screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    sign_in_through_ui

    visit new_advertising_order_path(grid_from: "2026-09-29", grid_to: "2026-10-02")
    check "order_screen_#{first_screen.id}"
    check "order_screen_#{second_screen.id}"
    select "3", from: "advertising_order_shows_per_hour"
    choose I18n.t("advertising_orders.form.distribution_strategies.chess")

    {
      "order-airtime-grid" => {
        first_screen.id => [ "30", "0" ],
        second_screen.id => [ "0", "30" ]
      },
      "order-airtime-grid-2026-10" => {
        first_screen.id => [ "30", "0" ],
        second_screen.id => [ "0", "30" ]
      }
    }.each do |table_id, expected_values|
      within("##{table_id}") do
        expected_values.each do |screen_id, values|
          row = find("[data-screen-id='#{screen_id}']")
          expect(row.all("[data-order-grid-target='cell']").map(&:value)).to eq(values)
        end
      end
    end
  end
end
