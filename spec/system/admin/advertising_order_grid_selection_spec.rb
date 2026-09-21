# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin advertising order grid selection", type: :system do
  include AdvertisingNetwork

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org, email: "ops@mediateca.test") }
  let(:client) { create(:organization, :client, name: "Triumph Org") }
  let(:group) { create_group_with_hours!(organization: client, name: "Витрины Триумф") }

  def named_screen
    group.screens.first.tap do |screen|
      screen.update!(name: "Витрина Триумф")
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
    fill_in I18n.t("sessions.new.email"), with: operator.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  def open_filled_grid
    create(:media_asset, :ready, :with_png_file, organization: client, duration_seconds: 10)
    screen = named_screen
    sign_in_through_ui
    visit new_admin_advertising_order_path(
      organization_id: client.id,
      grid_from: "2026-06-03",
      grid_to: "2026-06-05"
    )
    check "order_screen_#{screen.id}"
    select "3", from: "advertising_order_shows_per_hour"
    expect(page).to have_css("[data-order-grid-target='cell']", count: 3)
    expect(cell_values).to eq([ "36", "36", "36" ])
  end

  def cell_values
    all("[data-order-grid-target='cell']").map(&:value)
  end

  def marquee_select(from_index, to_index, shift: false)
    page.execute_script(<<~JS)
      const cells = [...document.querySelectorAll("[data-order-grid-target='cell']")]
      const from = cells[#{from_index}]
      const to = cells[#{to_index}]
      const fromBox = from.getBoundingClientRect()
      const toBox = to.getBoundingClientRect()
      const start = { x: fromBox.left + fromBox.width / 2, y: fromBox.top + fromBox.height / 2 }
      const end = { x: toBox.left + toBox.width / 2, y: toBox.top + toBox.height / 2 }
      const pointer = (type, point) => new PointerEvent(type, {
        bubbles: true,
        cancelable: true,
        pointerId: 1,
        pointerType: "mouse",
        isPrimary: true,
        button: type === "pointermove" ? -1 : 0,
        buttons: type === "pointerup" ? 0 : 1,
        clientX: point.x,
        clientY: point.y,
        shiftKey: #{shift}
      })
      from.dispatchEvent(pointer("pointerdown", start))
      window.dispatchEvent(pointer("pointermove", end))
      window.dispatchEvent(pointer("pointerup", end))
    JS
  end

  def shift_click_cell(index)
    page.execute_script(<<~JS)
      const cell = document.querySelectorAll("[data-order-grid-target='cell']")[#{index}]
      const box = cell.getBoundingClientRect()
      const point = { x: box.left + box.width / 2, y: box.top + box.height / 2 }
      const pointer = (type) => new PointerEvent(type, {
        bubbles: true,
        cancelable: true,
        pointerId: 1,
        pointerType: "mouse",
        isPrimary: true,
        button: 0,
        buttons: type === "pointerup" ? 0 : 1,
        clientX: point.x,
        clientY: point.y,
        shiftKey: true
      })
      cell.dispatchEvent(pointer("pointerdown"))
      window.dispatchEvent(pointer("pointerup"))
    JS
  end

  def click_cell(index)
    page.execute_script(<<~JS)
      const cell = document.querySelectorAll("[data-order-grid-target='cell']")[#{index}]
      const box = cell.getBoundingClientRect()
      const point = { x: box.left + box.width / 2, y: box.top + box.height / 2 }
      const pointer = (type) => new PointerEvent(type, {
        bubbles: true,
        cancelable: true,
        pointerId: 1,
        pointerType: "mouse",
        isPrimary: true,
        button: 0,
        buttons: type === "pointerup" ? 0 : 1,
        clientX: point.x,
        clientY: point.y
      })
      cell.dispatchEvent(pointer("pointerdown"))
      window.dispatchEvent(pointer("pointerup"))
    JS
  end

  def press_grid_key(key)
    page.execute_script(<<~JS)
      window.dispatchEvent(new KeyboardEvent("keydown", {
        key: #{key.to_json},
        bubbles: true,
        cancelable: true
      }))
    JS
  end

  it "zeros a dragged day range with 0", :js do
    open_filled_grid

    marquee_select(0, 1)
    press_grid_key("0")

    expect(cell_values).to eq([ "0", "0", "36" ])
    expect(find("[data-order-grid-target='total']").value).to eq("36")
  end

  it "zeros Shift-clicked days with x or space", :js do
    open_filled_grid

    click_cell(0)
    shift_click_cell(2)
    press_grid_key("x")
    expect(cell_values).to eq([ "0", "36", "0" ])

    click_cell(1)
    press_grid_key(" ")
    expect(cell_values).to eq([ "0", "0", "0" ])
    expect(find("[data-order-grid-target='total']").value).to eq("0")
  end

  it "creates the order after zeroing selected days with space", :js do
    open_filled_grid

    fill_in AdvertisingOrder.human_attribute_name(:product_name), with: "Triumph"
    select "1x1.png (10s)", from: "advertising_order_available_media_asset"
    marquee_select(0, 1)
    press_grid_key(" ")

    expect(cell_values).to eq([ "0", "0", "36" ])
    click_button I18n.t("advertising_orders.form.submit")

    expect(page).to have_content(I18n.t("advertising_orders.create.created"))
    order = AdvertisingOrder.last
    expect(order.product_name).to eq("Triumph")
    expect(order.advertising_order_lines.sole.advertising_order_line_days.order(:date).map(&:shows)).to eq([ 0, 0, 36 ])
  end
end
