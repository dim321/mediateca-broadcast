# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin advertising orders", type: :request do
  include AdvertisingNetwork

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:client) { create(:organization, :client, name: "Триумф", time_zone: "UTC") }
  let(:client_user) { create(:user, :manager, organization: client) }
  let(:sphere) { create(:directory_business_sphere, name: "Ритейл") }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: client, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: client) }

  def order_screen
    group.screens.first.tap do |screen|
      next if screen.broadcast_portrait.present?

      create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    end
  end

  def order_params(organization_id: client.id, screen: order_screen, dates: [ "2026-06-03" ], shows_per_hour: 3, **header)
    {
      advertising_order: {
        organization_id: organization_id,
        product_name: "Triumph",
        media_asset_id: asset.id,
        placement_kind: "own_atmosphere",
        shows_per_hour: shows_per_hour,
        windows: [ { starts_at: "09:00", ends_at: "12:00" } ],
        screen_ids: [ screen.id ],
        lines: {
          "0" => {
            screen_id: screen.id,
            days: dates.map { |date| { date: date, shows: 9 } }
          }
        }
      }.merge(header)
    }
  end

  describe "authentication" do
    it "denies client organization users" do
      sign_in_as(client_user)
      get admin_advertising_orders_path

      expect(response).to redirect_to(login_path)
    end
  end

  context "when signed in as operator" do
    before do
      create(:profile, organization: client, business_sphere: sphere, brand: "Triumph")
      sign_in_as(operator)
    end

    it "lists orders from client organizations" do
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )

      get admin_advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
      expect(order).to be_draft
    end

    it "shows an order and lets the operator cancel it" do
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      Advertising::ActivateOrder.call(order: order)

      get admin_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.advertising_orders.cancel"))
      expect(response.body).not_to include("Destroy")

      post cancel_admin_advertising_order_path(order)

      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.reload).to be_cancelled
    end

    def catalog_screen_on_group
      location = create(:location, name: "ТЦ Галерея", operating_hours: AdvertisingNetwork::WEEKLY_HOURS)
      station = create(:station, location: location, name: "Касса 1")
      screen = create(:screen, station: station, name: "Экран витрины", owner_organization: client)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
      create(:screen_tag, screen: screen, tag: create(:tag, name: "витрина"))
      create(:broadcast_portrait, :for_screen, screen: screen, name: "Цикл 4/час",
        block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
      screen
    end

    it "renders the screen picker before the airtime grid on the new form" do
      catalog_screen_on_group

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      body = response.body
      picker_at = body.index(I18n.t("advertising_orders.form.screens"))
      grid_at = body.index(I18n.t("advertising_orders.form.grid"))

      expect(response).to have_http_status(:success)
      expect(picker_at).to be_present.and be < grid_at
      expect(body).to include(
        "order-screen-picker",
        'data-order-screen-picker-target="showsPerHour"',
        'name="advertising_order[screen_ids][]"',
        'name="advertising_order[shows_per_hour]"',
        "advertising_order[windows]",
        I18n.t("advertising_orders.form.add_window")
      )
      expect(body).not_to match(/input[^>]*name="advertising_order\[shows_per_hour\]"[^>]*type="number"/)
      expect(body).not_to include("broadcast_point_group_id")
    end

    it "lists fleet screens and screens of other organizations" do
      fleet = create(:screen, name: "Флот оператора")
      other = create(:organization, :client)
      foreign = create(:screen, name: "Чужой экран", owner_organization: other)

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      expect(response.body).to include(fleet.name)
      expect(response.body).to include(foreign.name)
    end

    it "lists screens with location, station, tags, portrait, hours and column filters" do
      screen = catalog_screen_on_group

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      expect(response.body).to include(screen.name)
      expect(response.body).to include("ТЦ Галерея")
      expect(response.body).to include("Касса 1")
      expect(response.body).to include("витрина")
      expect(response.body).to include("Цикл 4/час")
      expect(response.body).to include("09:00")
      expect(response.body).to include(I18n.t("advertising_orders.form.screen_picker.filter_location"))
      expect(response.body).to include(I18n.t("advertising_orders.form.screen_picker.filter_hours"))
    end

    it "does not render coefficient or discount fields on the new form" do
      get new_admin_advertising_order_path, params: { organization_id: client.id }

      expect(response.body).not_to include('name="advertising_order[coefficient_percent]"')
      expect(response.body).not_to include('name="advertising_order[discount_rubles]"')
    end

    it "reloads the new form in the selected organization context" do
      operator_clip = create(:media_asset, :ready, :with_png_file, organization: operator_org)
      operator_clip.file.blob.update!(filename: "operator-only.mp4")
      asset.file.blob.update!(filename: "triumph-clip.mp4")

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("triumph-clip.mp4")
      expect(response.body).not_to include("operator-only.mp4")
      expect(response.body).to include("Ритейл")
      expect(response.body).to include(client.name)
    end

    it "does not change coefficient or discount from form params" do
      order = Advertising::CreateOrder.call(
        organization: client,
        created_by: client_user,
        media_asset: asset,
        product_name: "Triumph",
        coefficient_percent: 15,
        discount_cents: 1_000
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: advertising_order_grid_lines(screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      )

      patch admin_advertising_order_path(order), params: order_params(coefficient_percent: 99, discount_rubles: 50)

      expect(order.reload.coefficient_percent).to eq(15)
      expect(order.discount_cents).to eq(1_000)
    end

    it "lets an operator create an order for a client (AE11)" do
      expect {
        post admin_advertising_orders_path, params: order_params(dates: [ "2026-06-03" ])
      }.to change(AdvertisingOrder, :count).by(1)

      order = AdvertisingOrder.last
      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.organization).to eq(client)
      expect(order.created_by).to eq(operator)
      expect(order.business_sphere).to eq("Ритейл")
      expect(order.media_asset).to eq(asset)
      expect(order).to be_draft
    end

    it "lets the operator activate that order and the client see it in the cabinet (AE11)" do
      post admin_advertising_orders_path, params: order_params(dates: [ "2026-06-03" ])
      order = AdvertisingOrder.last

      post activate_admin_advertising_order_path(order)

      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.reload).to be_active
      expect(order.media_plans.active).to be_present

      sign_in_as(client_user)
      get advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
    end
  end
end
