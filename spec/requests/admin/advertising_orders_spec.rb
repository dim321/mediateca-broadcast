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

  def order_params(organization_id: client.id, group_id: group.id, shows: 36, price_rubles: 34_020, dates: [ "2026-06-03" ], **header)
    {
      advertising_order: {
        organization_id: organization_id,
        product_name: "Triumph",
        media_asset_id: asset.id,
        placement_kind: "own_atmosphere",
        coefficient_percent: 0,
        discount_rubles: 0,
        lines: {
          "0" => {
            broadcast_point_group_id: group_id,
            price_per_day_rubles: price_rubles,
            days: dates.map { |date| { date: date, shows: shows } }
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
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: group.id,
          price_per_day_cents: 1_000,
          days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
        } ]
      )
      Advertising::ActivateOrder.call(order: order)

      get admin_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("admin.advertising_orders.cancel"))
      expect(response.body).not_to include("Destroy")

      post cancel_admin_advertising_order_path(order)

      expect(response).to redirect_to(admin_advertising_order_path(order))
      expect(order.reload).to be_cancelled
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
