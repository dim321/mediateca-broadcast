# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AdvertisingOrders", type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def order_params(group_id: group.id, shows: 36, price_rubles: 34_020, dates: [ "2026-06-03" ], **header)
    {
      advertising_order: {
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

  def active_order
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
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
    order.reload
  end

  def clip_named(filename, duration:)
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: duration).tap do |record|
      record.file.blob.update!(filename: filename)
    end
  end

  describe "GET /advertising_orders" do
    it "lists orders of the client organization" do
      sign_in_as(user)
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_asset: asset,
        product_name: "Triumph"
      )

      get advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
      expect(response.body).to include(I18n.t("advertising_orders.index.new_order"))
      expect(order).to be_draft
    end

    it "filters by status" do
      sign_in_as(user)
      draft = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "DraftOnly"
      )
      active = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "ActiveOnly"
      )
      active.update!(status: :active)

      get advertising_orders_path, params: { status: "draft" }

      expect(response.body).to include(draft.product_name)
      expect(response.body).not_to include(active.product_name)
    end

    it "hides foreign organization orders" do
      sign_in_as(user)
      other = create(:organization, :client)
      Advertising::CreateOrder.call(
        organization: other,
        created_by: create(:user, :manager, organization: other),
        media_asset: create(:media_asset, :ready, :with_png_file, organization: other),
        product_name: "ForeignOrderXYZ"
      )

      get advertising_orders_path

      expect(response.body).not_to include("ForeignOrderXYZ")
    end

    it "lets the accountant read the list (AE10)" do
      sign_in_as(accountant)
      Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )

      get advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
    end
  end

  describe "POST /advertising_orders" do
    before { sign_in_as(user) }

    it "creates a draft with grid totals (AE1)" do
      expect do
        post advertising_orders_path, params: order_params(dates: [ "2026-06-03", "2026-06-04" ])
      end.to change(AdvertisingOrder, :count).by(1)

      order = AdvertisingOrder.last
      expect(response).to redirect_to(advertising_order_path(order))
      expect(order).to be_draft
      expect(order.total_shows).to eq(72)
      expect(order.total_sum_cents).to eq(2 * 34_020_00)
      expect(order.created_by).to eq(user)
    end

    it "rejects shows that are not a multiple of operating hours (AE2)" do
      eleven = create_group_with_hours!(organization: organization, hours: AdvertisingNetwork::ELEVEN_HOURS)

      expect do
        post advertising_orders_path, params: order_params(group_id: eleven.id, shows: 36)
      end.not_to change(AdvertisingOrderLineDay, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("33").and include("44")
    end

    it "rejects a line whose group has no operating hours (AE3)" do
      bare = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: bare, screen: create(:screen, owner_organization: organization))

      post advertising_orders_path, params: order_params(group_id: bare.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(AdvertisingOrderLine.count).to eq(0)
    end

    it "renders occupancy without foreign org ids" do
      other = create(:organization, :client, name: "ForeignOrgXYZ-NeverLeak")
      other_group = create(:broadcast_point_group, organization: other)
      create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen: group.screens.first)
      Airtime::OccupyWithPlan.call(
        organization: other,
        broadcast_point_group: other_group,
        rotation: create(:rotation, organization: other),
        starts_at: Time.utc(2026, 6, 3, 9, 0, 0),
        ends_at: Time.utc(2026, 6, 3, 10, 0, 0)
      )

      get new_advertising_order_path, params: {
        advertising_order: { broadcast_point_group_id: group.id },
        grid_from: "2026-06-01",
        grid_to: "2026-06-30"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("media_plans.occupied_slots.heading"))
      expect(response.body).to include('data-controller="order-grid"')
      expect(response.body).not_to include("ForeignOrgXYZ-NeverLeak")
      expect(response.body).not_to include("airtime_booking_id")
    end
  end

  describe "PATCH /advertising_orders/:id" do
    before { sign_in_as(user) }

    it "updates the draft grid and totals" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: group.id,
          price_per_day_cents: 1_000,
          days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
        } ]
      )

      patch advertising_order_path(order), params: order_params(dates: [ "2026-06-03", "2026-06-04" ], price_rubles: 25)

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload.total_shows).to eq(72)
      expect(order.total_sum_cents).to eq(2 * 25_00)
    end
  end

  describe "accountant mutations (AE10)" do
    before { sign_in_as(accountant) }

    it "denies create" do
      expect do
        post advertising_orders_path, params: order_params
      end.not_to change(AdvertisingOrder, :count)

      expect(response).to redirect_to(rails_health_check_path)
      expect(flash[:alert]).to be_present
    end

    it "denies activate" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )

      post activate_advertising_order_path(order)

      expect(response).to redirect_to(rails_health_check_path)
      expect(order.reload).to be_draft
    end

    it "allows print" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )

      get print_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("advertising.print_sheet.title"))
      expect(response.body).to match(/print-.*\.css/)
    end
  end

  describe "GET /advertising_orders/:id/print" do
    def printable_order
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_asset: asset,
        product_name: "Triumph",
        discount_cents: 1_000_00
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: group.id,
          price_per_day_cents: 34_020_00,
          days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
        } ]
      )
      order.reload
    end

    it "renders the print layout for a manager (A1)" do
      sign_in_as(user)
      order = printable_order

      get print_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("advertising.print_sheet.total_with_discount"))
      expect(response.body).to include(I18n.t("advertising.print_sheet.manager_signature"))
      expect(response.body).not_to include("cabinet-drawer")
    end

    it "allows the accountant to print (AE10)" do
      sign_in_as(accountant)
      order = printable_order

      get print_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
    end
  end

  describe "POST /advertising_orders/:id/activate" do
    before { sign_in_as(user) }

    def draft_with_days(dates:, shows: 36)
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: group.id,
          price_per_day_cents: 1_000,
          days: dates.map { |date| { date: date, shows: shows } }
        } ]
      )
      order
    end

    it "occupies the grid and shows the order" do
      order = draft_with_days(dates: [ Date.new(2026, 6, 3) ])

      post activate_advertising_order_path(order)

      expect(response).to redirect_to(advertising_order_path(order))
      follow_redirect!
      expect(order.reload).to be_active
      expect(order.media_plans.active.count).to eq(1)
      expect(response.body).to include(I18n.t("advertising_orders.activate.activated"))
    end

    it "keeps occupied windows and marks conflicted days (AE5)" do
      order = draft_with_days(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5) ])
      Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: group,
        rotation: create(:rotation, organization: organization),
        starts_at: Time.utc(2026, 6, 5, 0, 0, 0),
        ends_at: Time.utc(2026, 6, 6, 0, 0, 0)
      )

      post activate_advertising_order_path(order)
      follow_redirect!

      expect(order.reload).to be_active
      expect(order.media_plans.active.count).to eq(1)
      expect(response.body).to include(I18n.t("advertising_orders.show.unoccupied"))
      expect(response.body).to include(I18n.t("advertising_orders.show.occupy_again"))
    end

    it "aggregates commercial quota into one warning (AE6)" do
      owner = create(:organization, :client)
      owned = create_group_with_hours!(
        organization: owner,
        commercial_quota_percent: 10,
        commercial_quota_period: :hour
      )
      long_clip = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 240)
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_asset: long_clip,
        product_name: "Triumph",
        placement_kind: :commercial
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: owned.id,
          price_per_day_cents: 1_000,
          days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
        } ]
      )

      post activate_advertising_order_path(order)
      follow_redirect!

      expect(response.body.scan(I18n.t("advertising_orders.activate.quota_exceeded")).size).to eq(1)
    end
  end

  describe "GET /advertising_orders/:id/replace_clip" do
    it "shows the replacement form for a manager" do
      sign_in_as(user)
      order = active_order
      clip_named("triumph-v2.png", duration: 15)

      get replace_clip_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("triumph-v2.png")
      expect(response.body).to include(I18n.t("advertising_orders.replace_clip.duration_warning"))
    end

    it "denies the accountant (AE10)" do
      sign_in_as(accountant)
      order = active_order

      get replace_clip_advertising_order_path(order)

      expect(response).to redirect_to(rails_health_check_path)
    end
  end

  describe "PATCH /advertising_orders/:id/replace_clip" do
    it "replaces the clip, increments document version, and keeps slot ids (AE7)" do
      sign_in_as(user)
      order = active_order
      replacement = clip_named("triumph-v2.png", duration: 15)
      plan_ids = order.media_plans.order(:id).pluck(:id)

      patch replace_clip_advertising_order_path(order), params: { media_asset_id: replacement.id }

      expect(response).to redirect_to(advertising_order_path(order))
      follow_redirect!
      expect(order.reload.document_version).to eq(2)
      expect(order.media_asset).to eq(replacement)
      expect(order.clip_title).to eq("triumph-v2.png")
      expect(order.media_plans.order(:id).pluck(:id)).to eq(plan_ids)
      expect(response.body).to include(I18n.t("advertising_orders.replace_clip.replaced"))
      expect(response.body).to include(I18n.t("advertising_orders.show.document_version", version: 2))
    end

    it "shows the new version on the print page (AE7)" do
      sign_in_as(user)
      order = active_order
      replacement = clip_named("triumph-v2.png", duration: 15)
      Advertising::ReplaceClip.call(order: order, media_asset: replacement)

      get print_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("advertising.print_sheet.document_version", version: 2))
      expect(response.body).to include("triumph-v2.png")
    end

    it "rejects a not-ready clip" do
      sign_in_as(user)
      order = active_order
      pending_clip = create(
        :media_asset,
        :with_png_file,
        organization: organization,
        duration_seconds: 15,
        processing_status: "processing"
      )

      patch replace_clip_advertising_order_path(order), params: { media_asset_id: pending_clip.id }

      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.document_version).to eq(1)
      expect(order.media_asset).to eq(asset)
    end

    it "denies the accountant (AE10)" do
      sign_in_as(accountant)
      order = active_order
      replacement = clip_named("triumph-v2.png", duration: 15)

      patch replace_clip_advertising_order_path(order), params: { media_asset_id: replacement.id }

      expect(response).to redirect_to(rails_health_check_path)
      expect(order.reload.document_version).to eq(1)
    end
  end

  describe "POST /advertising_orders/:id/cancel" do
    before { sign_in_as(user) }

    it "cancels active slots and keeps document totals (AE8)" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: [ {
          broadcast_point_group_id: group.id,
          price_per_day_cents: 5_000,
          days: [ { date: Date.new(2026, 6, 3), shows: 36 } ]
        } ]
      )
      Advertising::ActivateOrder.call(order: order)
      total = order.reload.total_sum_cents

      post cancel_advertising_order_path(order)

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload).to be_cancelled
      expect(order.total_sum_cents).to eq(total)
      expect(order.media_plans.active).to be_empty
    end
  end

  describe "DELETE /advertising_orders/:id" do
    before { sign_in_as(user) }

    it "destroys a draft and its system rotation" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      rotation_id = order.rotation_id

      expect do
        delete advertising_order_path(order)
      end.to change(AdvertisingOrder, :count).by(-1)

      expect(Rotation.exists?(rotation_id)).to be false
      expect(response).to redirect_to(advertising_orders_path)
    end

    it "does not destroy an active order" do
      order = create(:advertising_order, organization: organization, created_by: user, status: :active)

      expect do
        delete advertising_order_path(order)
      end.not_to change(AdvertisingOrder, :count)

      expect(response).to redirect_to(rails_health_check_path)
    end
  end
end
