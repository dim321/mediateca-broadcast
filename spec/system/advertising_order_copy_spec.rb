# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Copying an advertising order from the list", type: :system do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization, email: "manager@copy.test") }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def order_screen
    group.screens.first.tap do |screen|
      next if screen.broadcast_portrait.present?

      create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    end
  end

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "reveals the copy button for the selected order and skips its dates", :js do
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
    )
    fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
    sign_in_through_ui
    visit advertising_orders_path

    expect(page).to have_button(I18n.t("advertising_orders.index.copy_order"), visible: :hidden)
    find("input[name='copy_order_id'][value='#{order.id}']").click
    click_button I18n.t("advertising_orders.index.copy_order")

    expect(page).to have_content(I18n.t("advertising_orders.copy.created"))
    expect(find("input[name='grid_from'][data-order-grid-date-target='display']").value).not_to eq("03.06.2026")
    expect(page).to have_no_css("input[value='03.06.2026']")
    expect(AdvertisingOrder.order(:id).last.advertising_order_line_days).to be_empty
  end
end
