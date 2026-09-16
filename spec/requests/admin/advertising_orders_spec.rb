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

    it "shows placement and media details on the order page" do
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(
        order,
        screen: order_screen,
        dates: [ Date.new(2026, 6, 1), Date.new(2026, 6, 2), Date.new(2026, 6, 4) ],
        shows: 9
      )

      get admin_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      details = Nokogiri::HTML(response.body).at_css("#advertising-order-details")

      expect(details).to be_present
      expect(details.css("h2").text).to include(I18n.t("admin.advertising_orders.show.details"))
      expect(details.text).to include(
        I18n.t("admin.advertising_orders.show.organization"),
        I18n.t("admin.advertising_orders.show.author"),
        I18n.t("admin.advertising_orders.show.business_sphere"),
        "01.06.2026–02.06.2026, 04.06.2026",
        "09:00–12:00",
        "3",
        asset.file.filename.to_s,
        "10",
        I18n.t("enums.media_asset.content_kind.image"),
        I18n.t("enums.media_asset.content_type.own"),
        order.total_shows.to_s
      )
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

    it "places placement kind beside the product and exposes selected clip metadata" do
      asset
      get new_admin_advertising_order_path, params: { organization_id: client.id }

      document = Nokogiri::HTML(response.body)
      product = document.at_css("#advertising_order_product_name")
      placement = document.at_css("#advertising_order_placement_kind")
      clip = document.at_css("#advertising_order_media_asset_id")
      option = clip.at_css("option[value='#{asset.id}']")

      expect([ product, placement, clip, option ]).to all(be_present)
      expect(product.parent.parent["class"]).to include("grid")
      expect(product.parent.parent.text).to include(
        AdvertisingOrder.human_attribute_name(:product_name),
        AdvertisingOrder.human_attribute_name(:placement_kind)
      )
      expect(option.to_s).to include(
        'data-duration="10"',
        "data-content-type=\"#{I18n.t("media_assets.index.content_types.own")}\"",
        "data-content-kind=\"#{I18n.t("media_assets.index.content_kinds.image")}\""
      )
      expect(document.at_css("[data-order-media-asset-target='details']")).to be_present
    end

    it "defaults new orders to commercial placement" do
      get new_admin_advertising_order_path, params: { organization_id: client.id }

      placement = Nokogiri::HTML(response.body).at_css("#advertising_order_placement_kind")

      expect(placement.at_css("option[value='commercial'][selected]")).to be_present
    end

    it "lists fleet screens and screens of other organizations" do
      fleet = create(:screen, name: "Флот оператора")
      other = create(:organization, :client)
      foreign = create(:screen, name: "Чужой экран", owner_organization: other)

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      expect(response.body).to include(fleet.name)
      expect(response.body).to include(foreign.name)
    end

    it "lists screens with location, tags, portrait frequencies, hours and column filters" do
      screen = catalog_screen_on_group

      get new_admin_advertising_order_path, params: { organization_id: client.id }

      table = Nokogiri::HTML(response.body).at_css("table.table")
      expect(table).to be_present
      text = table.text
      headers = table.css("thead tr").first.css("th").map { |th| th.text.strip }

      expect(text).to include(screen.name, "ТЦ Галерея", "витрина", "1, 2, 3, 4, 6", "09:00")
      expect(text).not_to include("Касса 1", "Цикл 4/час")
      expect(headers).to include(BroadcastPortrait.human_attribute_name(:block_frequencies_per_hour))
      expect(headers).not_to include(Station.model_name.human, BroadcastPortrait.model_name.human)
      expect(response.body).to include(
        I18n.t("advertising_orders.form.screen_picker.filter_location"),
        I18n.t("advertising_orders.form.screen_picker.filter_frequencies"),
        I18n.t("advertising_orders.form.screen_picker.filter_hours")
      )
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

    it "shows ready media assets on a draft order edit form" do
      replacement = create(:media_asset, :ready, :with_png_file, organization: client)
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )

      get edit_admin_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="advertising_order[media_asset_id]"')
      expect(response.body).to include(replacement.file.filename.to_s)
    end

    it "replaces the draft media asset and preserves its grid" do
      replacement = create(:media_asset, :ready, :with_png_file, organization: client, duration_seconds: 15)
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      original_line_ids = order.advertising_order_lines.pluck(:id)

      patch admin_advertising_order_path(order), params: order_params(media_asset_id: replacement.id)

      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.reload.media_asset).to eq(replacement)
      expect(order.advertising_order_lines.pluck(:id)).to eq(original_line_ids)
      expect(order.rotation.ordered_items.sole.media_asset).to eq(replacement)
    end

    it "rejects a media asset outside the order organization" do
      foreign_asset = create(:media_asset, :ready, :with_png_file, organization: operator_org)
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )

      patch admin_advertising_order_path(order), params: order_params(media_asset_id: foreign_asset.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.media_asset).to eq(asset)
    end

    it "rejects a media asset that is not ready" do
      pending_asset = create(
        :media_asset,
        :with_png_file,
        organization: client,
        processing_status: :processing
      )
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )

      patch admin_advertising_order_path(order), params: order_params(media_asset_id: pending_asset.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.media_asset).to eq(asset)
    end

    it "does not expose or replace media on an active order" do
      replacement = create(:media_asset, :ready, :with_png_file, organization: client)
      order = Advertising::CreateOrder.call(
        organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      Advertising::ActivateOrder.call(order: order)

      get edit_admin_advertising_order_path(order)
      expect(response.body).not_to include('name="advertising_order[media_asset_id]"')

      patch admin_advertising_order_path(order), params: order_params(media_asset_id: replacement.id)

      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.reload.media_asset).to eq(asset)
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
