# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AdvertisingOrders", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, :client) }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:traffic_manager) { create(:user, :traffic_manager, organization: organization) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }

  def order_screen
    group.screens.first.tap do |screen|
      next if screen.broadcast_portrait.present?

      create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    end
  end

  def order_params(screen: order_screen, dates: [ "2026-06-03" ], shows_per_hour: 3, media_assets: [ asset ], grid_from: nil, grid_to: nil, **header)
    params = {
      advertising_order: {
        product_name: "Triumph",
        media_asset_ids: media_assets.map(&:id),
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
    params[:grid_from] = grid_from if grid_from
    params[:grid_to] = grid_to if grid_to
    params
  end

  def active_order
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
    )
    fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  def clip_named(filename, duration:)
    create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: duration).tap do |record|
      record.file.blob.update!(filename: filename)
    end
  end

  describe "GET /advertising_orders" do
    it "roots the cabinet at advertising orders" do
      sign_in_as(user)
      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("layouts.application.advertising_orders"))
      expect(response.body).to include(I18n.t("advertising_orders.index.new_order"))
    end

    it "lists orders of the client organization" do
      sign_in_as(user)
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ asset ],
        product_name: "Triumph"
      )

      get advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
      expect(response.body).to include(I18n.t("advertising_orders.index.new_order"))
      expect(order).to be_draft
    end

    it "shows a rejection reason to the order author" do
      sign_in_as(user)
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "RejectedOrder"
      )
      order.update!(status: :rejected, rejection_reason: :content_problem)
      reason = I18n.t("enums.advertising_order.rejection_reason.content_problem")

      get advertising_order_path(order)

      expect(response.body).to include(I18n.t("advertising_orders.show.rejected", reason: reason))
      expect(response.body).to include(I18n.t("advertising_orders.show.edit_rejected"))
      status = Nokogiri::HTML(response.body).at_css("#advertising-order-status")
      expect(status.text).to include(I18n.t("enums.advertising_order.status.rejected"), reason)

      get advertising_orders_path

      expect(response.body).to include("RejectedOrder")
      card_status = Nokogiri::HTML(response.body).at_css(".order-status")
      expect(card_status.text).to include(I18n.t("enums.advertising_order.status.rejected"), reason)
    end

    it "filters by status" do
      sign_in_as(user)
      draft = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "DraftOnly"
      )
      active = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "ActiveOnly"
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
        media_assets: [ create(:media_asset, :ready, :with_png_file, organization: other) ],
        product_name: "ForeignOrderXYZ"
      )

      get advertising_orders_path

      expect(response.body).not_to include("ForeignOrderXYZ")
    end

    it "lets the accountant read the list (AE10)" do
      sign_in_as(accountant)
      Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )

      get advertising_orders_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Triumph")
      expect(response.body).not_to include(I18n.t("advertising_orders.index.copy_order"))
    end
  end

  describe "POST /advertising_orders/:id/copy" do
    def source_order
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ asset ],
        product_name: "Triumph",
        placement_kind: :commercial,
        shows_per_hour: 4,
        distribution_strategy: :chess,
        coefficient_percent: 15,
        discount_cents: 1_000
      )
      fill_order_grid!(
        order,
        screen: order_screen,
        dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5) ],
        shows_per_hour: 4,
        windows: [ { starts_at: "10:00", ends_at: "18:00" } ]
      )
      order.update!(distribution_strategy: :chess, coefficient_percent: 15, discount_cents: 1_000, document_version: 3)
      order
    end

    it "offers a hidden copy button and a single-choice radio" do
      sign_in_as(user)
      order = source_order

      get advertising_orders_path

      document = Nokogiri::HTML(response.body)
      button = document.css("button").find { |node| node.text.include?(I18n.t("advertising_orders.index.copy_order")) }
      expect(button["hidden"]).to eq("hidden")
      expect(button["disabled"]).to eq("disabled")
      expect(document.at_css("input[type='radio'][name='copy_order_id'][value='#{order.id}']")).to be_present
    end

    it "creates a draft from the selected order without its dates" do
      sign_in_as(user)
      source = source_order

      travel_to Time.zone.local(2026, 10, 3, 12) do
        expect do
          post copy_advertising_order_path(source)
        end.to change(AdvertisingOrder, :count).by(1)
          .and have_enqueued_mail(AdvertisingOrderMailer, :draft_created)

        copy = AdvertisingOrder.order(:id).last
        expect(response).to redirect_to(edit_advertising_order_path(copy))
        expect(copy).to be_draft.and have_attributes(
          created_by: user,
          product_name: "Triumph",
          placement_kind: "commercial",
          shows_per_hour: 4,
          distribution_strategy: "chess",
          coefficient_percent: 15,
          discount_cents: 1_000,
          document_version: 1
        )
        expect(copy.rotation.ordered_items.map(&:media_asset)).to eq([ asset ])
        expect(copy.advertising_order_lines.map { |line| [ line.screen, line.advertising_order_line_days.to_a ] })
          .to eq([ [ order_screen, [] ] ])
        expect(copy.advertising_order_windows.map { |window| window.starts_at.strftime("%H:%M") }).to eq([ "10:00" ])

        follow_redirect!
        from = Nokogiri::HTML(response.body).css("input[name='grid_from']").find { |node| node["type"] != "hidden" }
        expect(from["value"]).to eq("04.10.2026")
        expect(flash[:notice]).to eq(I18n.t("advertising_orders.copy.created"))
      end
    end

    it "does not copy an order from another organization" do
      sign_in_as(user)
      other = create(:organization, :client)
      foreign = Advertising::CreateOrder.call(
        organization: other,
        created_by: create(:user, :manager, organization: other),
        media_assets: [ create(:media_asset, :ready, :with_png_file, organization: other) ],
        product_name: "ForeignOrderXYZ"
      )

      expect do
        post copy_advertising_order_path(foreign)
      end.not_to change(AdvertisingOrder, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /advertising_orders" do
    before { sign_in_as(user) }

    it "creates a draft with grid totals (AE1)" do
      expect do
        post advertising_orders_path, params: order_params(dates: [ "2026-06-03", "2026-06-04" ])
      end.to change(AdvertisingOrder, :count).by(1)
        .and have_enqueued_mail(AdvertisingOrderMailer, :draft_created)

      order = AdvertisingOrder.last
      window = order.advertising_order_windows.sole
      expect(response).to redirect_to(advertising_order_path(order))
      expect(flash[:notice]).to eq(I18n.t("advertising_orders.create.created", name: order.product_name))
      expect(order).to be_draft.and have_attributes(
        shows_per_hour: 3,
        total_shows: 18,
        total_sum_cents: 0,
        created_by: user
      )
      expect(order.rotation.ordered_items.sole.media_asset).to eq(asset)
      expect(window.starts_at.strftime("%H:%M")).to eq("09:00")
      expect(window.ends_at.strftime("%H:%M")).to eq("12:00")
    end

    it "creates a draft with multiple clips in catalog order" do
      second = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12)

      expect do
        post advertising_orders_path, params: order_params(media_assets: [ asset, second ])
      end.to change(AdvertisingOrder, :count).by(1)

      order = AdvertisingOrder.last
      expect(order.media_asset_id).to be_nil
      expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ asset, second ])
    end

    it "rejects create without clips" do
      orders = AdvertisingOrder.count

      expect do
        post advertising_orders_path, params: order_params(media_assets: [])
      end.not_to have_enqueued_mail(AdvertisingOrderMailer, :draft_created)

      expect(AdvertisingOrder.count).to eq(orders)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects duplicate clips on create" do
      expect do
        post advertising_orders_path, params: order_params(media_assets: [ asset, asset ])
      end.not_to change(AdvertisingOrder, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a foreign clip on create" do
      foreign = create(:media_asset, :ready, :with_png_file, organization: create(:organization, :client))

      expect do
        post advertising_orders_path, params: order_params(media_assets: [ foreign ])
      end.not_to change(AdvertisingOrder, :count)

      expect(response).to have_http_status(:unprocessable_content)
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
      order_screen
      get new_advertising_order_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(
        I18n.t("advertising_orders.form.grid"),
        "order-screen-picker",
        'data-order-screen-picker-target="showsPerHour"',
        "advertising_order[screen_ids][]",
        'name="advertising_order[shows_per_hour]"',
        "advertising_order[windows]",
        I18n.t("advertising_orders.form.add_window"),
        "order-grid#startSelection",
        "order-grid#selectionKeydown:capture",
        I18n.t("advertising_orders.form.grid_legend.select_days")
      )
      expect(response.body).not_to match(/input[^>]*name="advertising_order\[shows_per_hour\]"[^>]*type="number"/)
      expect(response.body).not_to include("broadcast_point_group_id")
    end

    it "renders shows_per_hour select disabled with blank only until screens are selected" do
      order_screen
      get new_advertising_order_path

      select = Nokogiri::HTML(response.body).at_css("#advertising_order_shows_per_hour")
      expect(select).to be_present

      classes = select["class"].to_s.split
      expect(classes).to include("w-20")
      expect(classes).not_to include("w-full")
      expect(select["disabled"]).to eq("disabled")
      option_values = select.css("option").map { |option| option["value"] }
      expect(option_values).to eq([ "" ])
      expect(option_values.none? { |value| value.match?(/\A\d+\z/) }).to be(true)
    end

    it "re-renders shows_per_hour options from portrait intersection when screen_ids are posted" do
      screen = order_screen
      post advertising_orders_path, params: {
        grid_from: "2026-06-03",
        grid_to: "2026-06-05",
        advertising_order: {
          product_name: "",
          media_asset_id: asset.id,
          screen_ids: [ screen.id ],
          windows: [ { starts_at: "08:00", ends_at: "23:00" } ]
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      select = Nokogiri::HTML(response.body).at_css("#advertising_order_shows_per_hour")
      expect(select["disabled"]).to be_nil
      option_values = select.css("option").map { |option| option["value"] }.reject(&:blank?)
      expect(option_values).to eq(Portraits::FrequencySet.intersection_for_screens([ screen ]).map(&:to_s))
    end

    it "defaults the first day window to 08:00–23:00" do
      get new_advertising_order_path

      list = Nokogiri::HTML(response.body).at_css("[data-order-windows-target='list']")
      expect(list.at_css("[data-order-grid-target='windowStart']")["value"]).to eq("08:00")
      expect(list.at_css("[data-order-grid-target='windowEnd']")["value"]).to eq("23:00")
      expect(list.at_css("[data-order-windows-part='start-hour'] option[selected]")["value"]).to eq("08")
      expect(list.at_css("[data-order-windows-part='start-minute'] option[selected]")["value"]).to eq("00")
      expect(list.at_css("[data-order-windows-part='end-hour'] option[selected]")["value"]).to eq("23")
      expect(list.at_css("[data-order-windows-part='end-minute'] option[selected]")["value"]).to eq("00")
      expect(list.at_css("[data-order-windows-part='start-hour']").css("option").map { |option| option["value"] }).to eq(
        [ "" ] + (0..23).map { |number| format("%02d", number) }
      )
      expect(list.at_css("[data-order-windows-automatic='true']")).to be_present
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

    it "adds a calendar picker to С/По without changing the submitted date format" do
      get new_advertising_order_path, params: { grid_from: "2026-06-03", grid_to: "2026-06-05" }

      html = Nokogiri::HTML(response.body)
      pickers = html.css("[data-order-grid-date-target='picker']")
      expect(html.at_css("[data-controller='order-grid-date']")).to be_present
      expect(pickers.map { |node| node["type"] }.uniq).to eq([ "date" ])
      expect(pickers.map { |node| node["name"] }).to all(be_blank)
      expect(pickers.map { |node| node["value"] }).to contain_exactly("2026-06-03", "2026-06-05")
      expect(visible_grid_date_input("grid_from")["value"]).to eq("03.06.2026")
    end

    it "accepts dotted С/По dates when showing the grid" do
      get new_advertising_order_path, params: { grid_from: "03.06.2026", grid_to: "05.06.2026" }

      expect(visible_grid_date_input("grid_from")["value"]).to eq("03.06.2026")
      expect(visible_grid_date_input("grid_to")["value"]).to eq("05.06.2026")
      month_label = "Июнь 2026"
      thead = Nokogiri::HTML(response.body).at_css("#order-airtime-grid thead")
      expect(thead.text).to include(month_label)
    end

    it "labels the media asset select in Russian" do
      get new_advertising_order_path

      expect(response.body).to include(I18n.t("advertising_orders.form.clips"))
      expect(response.body).to include('data-controller="order-media-assets"')
      expect(response.body).to include('name="advertising_order[media_asset_ids][]"')
      expect(response.body).not_to include('id="advertising_order_media_asset_id"')
    end

    it "embeds every open clock hour so extra windows can be applied in the browser" do
      screen = order_screen
      get new_advertising_order_path, params: { grid_from: "2026-06-03", grid_to: "2026-06-03" }

      html = Nokogiri::HTML(response.body)
      row = html.at_css("[data-order-screen-picker-target='row'][data-screen-id='#{screen.id}']")
      hours = JSON.parse(row["data-hours"])
      expect(hours.fetch("2026-06-03")).to eq((9..20).to_a)
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
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
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

    it "gives day show cells enough width for two-digit values" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ], shows: 9)

      get edit_advertising_order_path(order), params: { grid_from: "2026-06-03", grid_to: "2026-06-03" }

      cell = Nokogiri::HTML(response.body).at_css("[data-order-grid-target='cell']")
      expect(cell["class"]).to include("w-14")
      expect(cell["class"]).to include("min-w-14")
    end

    it "locks product name and past grid cells on an active order" do
      travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
        organization.update!(time_zone: "UTC")
        order = Advertising::CreateOrder.call(
          organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
        )
        fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
        Advertising::ActivateOrder.call(order: order)

        get edit_advertising_order_path(order), params: { grid_from: "2026-06-03", grid_to: "2026-06-06" }

        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        product_name = html.at_css('input[name="advertising_order[product_name]"]')
        expect(product_name["disabled"]).to eq("disabled")
        locked_cell = html.at_css('[data-order-grid-target="cell"][data-date="2026-06-03"]')
        expect(locked_cell["disabled"]).to eq("disabled")
        grid_to = html.css("input[name='grid_to']").find { |node| node["type"] != "hidden" }
        expect(grid_to["max"]).to eq("2026-06-06")
      end
    end

    it "shows the month once in the grid header instead of each screen row" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4) ], shows: 9)

      get edit_advertising_order_path(order), params: { grid_from: "2026-06-03", grid_to: "2026-06-04" }

      html = Nokogiri::HTML(response.body)
      month_label = "Июнь 2026"
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
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      Advertising::UpdateGrid.call(
        order: order,
        lines: advertising_order_grid_lines(screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      )

      expect do
        patch advertising_order_path(order), params: order_params(dates: [ "2026-06-03", "2026-06-04" ])
      end.not_to have_enqueued_mail(AdvertisingOrderMailer, :draft_created)

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload.total_shows).to eq(18)
      expect(order.total_sum_cents).to eq(0)
    end

    it "does not change coefficient or discount from form params" do
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ asset ],
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

    it "shows the rejection reason and a resubmit action on the edit form" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      Advertising::RejectOrder.call(order: order, rejection_reason: "invalid_points")
      reason = I18n.t("enums.advertising_order.rejection_reason.invalid_points")

      get edit_advertising_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("advertising_orders.show.rejected", reason: reason))
      expect(response.body).to include(I18n.t("advertising_orders.form.resubmit"))
    end

    it "returns a rejected order to draft so a traffic manager can activate it" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
      Advertising::RejectOrder.call(order: order, rejection_reason: "invalid_points")

      patch advertising_order_path(order), params: order_params(
        dates: [ "2026-06-03", "2026-06-04" ],
        product_name: "Fixed"
      )

      expect(response).to redirect_to(advertising_order_path(order))
      expect(flash[:notice]).to eq(I18n.t("advertising_orders.update.resubmitted"))
      expect(order.reload).to have_attributes(
        status: "draft",
        rejection_reason: nil,
        product_name: "Fixed",
        total_shows: 18
      )

      sign_in_as(traffic_manager)
      post activate_advertising_order_path(order)

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload).to be_active
    end

    it "keeps a rejected order rejected when the edit is invalid" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      Advertising::RejectOrder.call(order: order, rejection_reason: "content_problem")

      patch advertising_order_path(order), params: order_params(product_name: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("advertising_orders.form.resubmit"))
      expect(order.reload).to be_rejected
      expect(order).to be_content_problem
      expect(order.product_name).to eq("Triumph")
    end

    it "denies a traffic manager and an accountant from editing a rejected order" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      Advertising::RejectOrder.call(order: order, rejection_reason: "other")

      [ traffic_manager, accountant ].each do |actor|
        sign_in_as(actor)

        get edit_advertising_order_path(order)

        expect(response).to redirect_to(rails_health_check_path)
        expect(order.reload).to be_rejected
      end
    end

    it "updates the draft clip list" do
      replacement = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 15)
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])

      patch advertising_order_path(order), params: order_params(media_assets: [ replacement, asset ])

      expect(response).to redirect_to(advertising_order_path(order))
      expect(order.reload.rotation.ordered_items.map(&:media_asset)).to eq([ replacement, asset ])
    end

    it "rejects a foreign clip on draft update" do
      foreign = create(:media_asset, :ready, :with_png_file, organization: create(:organization, :client))
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )

      patch advertising_order_path(order), params: order_params(media_assets: [ foreign ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(asset)
    end

    it "lets a manager revise frequency on an active order" do
      travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
        order = Advertising::CreateOrder.call(
          organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
        )
        fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
        Advertising::ActivateOrder.call(order: order)
        rotation_item_id = order.rotation.ordered_items.sole.id

        patch advertising_order_path(order), params: order_params(
          dates: [ "2026-06-03", "2026-06-06" ],
          shows_per_hour: 6,
          grid_from: "2026-06-03",
          grid_to: "2026-06-06"
        )

        expect(response).to redirect_to(advertising_order_path(order))
        order.reload
        expect(order.shows_per_hour).to eq(6)
        expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
        expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 6)).shows).to eq(18)
        expect(order.rotation.ordered_items.sole.id).to eq(rotation_item_id)
      end
    end

    it "rejects a tampered grid start on an active order" do
      travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
        order = Advertising::CreateOrder.call(
          organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
        )
        fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
        Advertising::ActivateOrder.call(order: order)

        patch advertising_order_path(order), params: order_params(
          dates: [ "2026-06-03", "2026-06-06" ],
          grid_from: "2026-06-04",
          grid_to: "2026-06-06"
        )

        expect(response).to have_http_status(:unprocessable_content)
        expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(
          Date.new(2026, 6, 3), Date.new(2026, 6, 6)
        )
      end
    end

    it "replaces clips on an active order and enqueues playlist regen" do
      travel_to Time.utc(2026, 9, 2, 10, 0, 0) do
        replacement = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 15)
        order = Advertising::CreateOrder.call(
          organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
        )
        fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 9, 3) ])
        Advertising::ActivateOrder.call(order: order)
        station_id = order_screen.station_id

        expect {
          patch replace_clip_advertising_order_path(order), params: { media_asset_ids: [ replacement.id ] }
        }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station_id, "2026-09-03")

        expect(response).to redirect_to(advertising_order_path(order))
        expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(replacement)
        expect(order.document_version).to eq(2)
      end
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
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )

      post activate_advertising_order_path(order)

      expect(response).to redirect_to(rails_health_check_path)
      expect(order.reload).to be_draft
    end

    it "allows print" do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )

      get print_advertising_order_path(order)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("advertising.print_sheet.title"))
      expect(response.body).to match(/print-.*\.css/)
    end

    it "denies patch on an active order" do
      travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
        order = Advertising::CreateOrder.call(
          organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
        )
        fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
        Advertising::ActivateOrder.call(order: order)

        patch advertising_order_path(order), params: order_params(
          dates: [ "2026-06-03", "2026-06-06" ],
          shows_per_hour: 6,
          grid_from: "2026-06-03",
          grid_to: "2026-06-06"
        )

        expect(response).to redirect_to(rails_health_check_path)
        expect(order.reload.shows_per_hour).to eq(3)
      end
    end
  end

  describe "GET /advertising_orders/:id/print" do
    def printable_order
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ asset ],
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
    before { sign_in_as(traffic_manager) }

    def draft_with_days(dates:, shows: 9)
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
      )
      fill_order_grid!(order, screen: order_screen, dates: dates, shows: shows)
      order
    end

    it "denies the manager who created the draft and shows a disabled activate button" do
      order = draft_with_days(dates: [ Date.new(2026, 6, 3) ])
      sign_in_as(user)

      get advertising_order_path(order)

      expect(response.body).to include(I18n.t("advertising_orders.show.activate"))
      expect(response.body).to include("disabled")

      post activate_advertising_order_path(order)

      expect(response).to redirect_to(rails_health_check_path)
      expect(order.reload).to be_draft
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
      long_clip = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 240)
      order = Advertising::CreateOrder.call(
        organization: organization,
        created_by: user,
        media_assets: [ long_clip ],
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
      expect(order.primary_media_asset).to eq(replacement)
      expect(order.clip_title).to eq("triumph-v2.png")
      expect(order.media_plans.order(:id).pluck(:id)).to eq(plan_ids)
      expect(response.body).to include(I18n.t("advertising_orders.replace_clip.replaced"))
      expect(response.body).to include(I18n.t("advertising_orders.show.document_version", version: 2))
    end

    it "shows the new version on the print page (AE7)" do
      sign_in_as(user)
      order = active_order
      replacement = clip_named("triumph-v2.png", duration: 15)
      Advertising::UpdateOrderClips.call(order: order, media_assets: [ replacement ])

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
      expect(order.rotation.ordered_items.sole.media_asset).to eq(asset)
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
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
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
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph"
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
