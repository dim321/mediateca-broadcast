# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AdvertisingOrders", type: :request do
  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def order_screen
    group.screens.first
  end

  def order_params(screen: order_screen, dates: [ "2026-06-03" ], shows_per_hour: 3, **header)
    {
      advertising_order: {
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

  def active_order
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
    )
    fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
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
      expect(order.shows_per_hour).to eq(3)
      expect(order.advertising_order_windows.sole.starts_at.strftime("%H:%M")).to eq("09:00")
      expect(order.advertising_order_windows.sole.ends_at.strftime("%H:%M")).to eq("12:00")
      expect(order.total_shows).to eq(18)
      expect(order.total_sum_cents).to eq(0)
      expect(order.created_by).to eq(user)
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
        advertising_order: { screen_ids: [ group.screens.first.id ] },
        grid_from: "2026-06-01",
        grid_to: "2026-06-30"
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("media_plans.occupied_slots.heading"))
      expect(response.body).to include('data-controller="order-grid')
      expect(response.body).not_to include("ForeignOrgXYZ-NeverLeak")
      expect(response.body).not_to include("airtime_booking_id")
    end
  end

  describe "GET /advertising_orders/new" do
    before { sign_in_as(user) }

    def visible_grid_date_input(name)
      Nokogiri::HTML(response.body).css("input[name='#{name}']").find { |node| node["type"] != "hidden" }
    end

    it "renders the screen picker, hourly rate, and day windows" do
      get new_advertising_order_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("advertising_orders.form.grid"))
      expect(response.body).to include("order-screen-picker")
      expect(response.body).to include('name="advertising_order[shows_per_hour]"')
      expect(response.body).to include("advertising_order[windows]")
      expect(response.body).to include(I18n.t("advertising_orders.form.add_window"))
      expect(response.body).not_to include("broadcast_point_group_id")
    end

    it "does not render coefficient or discount fields" do
      get new_advertising_order_path

      expect(response.body).not_to include('name="advertising_order[coefficient_percent]"')
      expect(response.body).not_to include('name="advertising_order[discount_rubles]"')
    end

    it "shows С/По dates as dd.mm.yyyy text fields" do
      get new_advertising_order_path, params: { grid_from: "2026-06-03", grid_to: "2026-06-05" }

      from = visible_grid_date_input("grid_from")
      to = visible_grid_date_input("grid_to")
      expect(from["type"]).to eq("text")
      expect(to["type"]).to eq("text")
      expect(from["value"]).to eq("03.06.2026")
      expect(to["value"]).to eq("05.06.2026")
    end

    it "accepts dotted С/По dates when showing the grid" do
      get new_advertising_order_path, params: { grid_from: "03.06.2026", grid_to: "05.06.2026" }

      expect(visible_grid_date_input("grid_from")["value"]).to eq("03.06.2026")
      expect(visible_grid_date_input("grid_to")["value"]).to eq("05.06.2026")
      month_label = I18n.l(Date.new(2026, 6, 1), format: "%B %Y")
      thead = Nokogiri::HTML(response.body).at_css("#order-airtime-grid thead")
      expect(thead.text).to include(month_label)
    end

    it "labels the media asset select in Russian" do
      get new_advertising_order_path

      expect(AdvertisingOrder.human_attribute_name(:media_asset_id)).to eq("Ролик")
      expect(response.body).to include("Ролик")
    end
  end

  describe "GET /advertising_orders/:id/edit" do
    before { sign_in_as(user) }

    it "shows screen and location on the grid row with a total shows field" do
      screen = order_screen
      screen.update!(name: "Витрина 7")
      screen.location.update!(name: "ТЦ Галерея")
      screen.station.update!(name: "Станция Невидимая")
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4) ], shows: 9)

      get edit_advertising_order_path(order), params: { grid_from: "2026-06-03", grid_to: "2026-06-04" }

      html = Nokogiri::HTML(response.body)
      row = html.at_css("[data-order-grid-target='lineRow']")
      expect(row.name).to eq("tr")
      expect(row.text).to include("Витрина 7")
      expect(row.text).to include("ТЦ Галерея")
      expect(row.text).not_to include("Станция Невидимая")
      expect(row.at_css("[data-order-screen-picker-target='screenName']")).to be_present
      expect(row.at_css("[data-order-grid-target='total']")["value"]).to eq("18")
      expect(html.at_css("[data-order-grid-target='grandTotal']")["value"]).to eq("18")
    end

    it "shows the month once in the grid header instead of each screen row" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4) ], shows: 9)

      get edit_advertising_order_path(order), params: { grid_from: "2026-06-03", grid_to: "2026-06-04" }

      html = Nokogiri::HTML(response.body)
      month_label = I18n.l(Date.new(2026, 6, 1), format: "%B %Y")
      thead = html.at_css("#order-airtime-grid thead")
      row = html.at_css("[data-order-grid-target='lineRow']")
      expect(thead.text).to include(month_label)
      expect(thead.text.scan(month_label).size).to eq(1)
      expect(row.text).not_to include(month_label)
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
        lines: advertising_order_grid_lines(screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      )

      patch advertising_order_path(order), params: order_params(dates: [ "2026-06-03", "2026-06-04" ])

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload.total_shows).to eq(18)
      expect(order.total_sum_cents).to eq(0)
    end

    it "does not change coefficient or discount from form params" do
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_asset: asset,
        product_name: "Triumph",
        coefficient_percent: 15,
        discount_cents: 1_000
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: advertising_order_grid_lines(screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      )

      patch advertising_order_path(order), params: order_params(coefficient_percent: 99, discount_rubles: 50)

      expect(order.reload.coefficient_percent).to eq(15)
      expect(order.discount_cents).to eq(1_000)
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
        lines: advertising_order_grid_lines(screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
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

    def draft_with_days(dates:, shows: 9)
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_asset: asset, product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: dates, shows: shows)
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
      fill_order_grid!(order, screen: owned.screens.first, dates: [ Date.new(2026, 6, 3) ])

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
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
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
