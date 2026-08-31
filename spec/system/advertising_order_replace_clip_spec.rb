# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advertising order clip replacement", type: :system do
  let(:organization) { create(:organization, :client, name: "Triumph Org") }
  let(:user) { create(:user, :manager, organization: organization, email: "manager@triumph.test") }
  let(:original) { clip_named("triumph-v1.png", duration: 10) }
  let(:replacement) { clip_named("triumph-v2.png", duration: 15) }
  let(:group) { create_group_with_hours!(organization: organization, name: "Витрины Триумф") }

  def clip_named(filename, duration:)
    create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: duration).tap do |asset|
      asset.file.blob.update!(filename: filename)
    end
  end

  def sign_in_through_ui
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  def activate_order_on!(date)
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: original,
      product_name: "Triumph"
    )
    Advertising::UpdateGrid.call(
      order: order,
      lines: [ {
        broadcast_point_group_id: group.id,
        price_per_day_cents: 1_000,
        days: [ { date: date, shows: 36 } ]
      } ]
    )
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations -- one end-to-end journey
  it "replaces the clip so the station package plays the new one" do
    replacement
    order = activate_order_on!(Date.current)
    plan_id = order.media_plans.sole.id
    sign_in_through_ui

    visit advertising_order_path(order)
    click_link I18n.t("advertising_orders.show.replace_clip")
    expect(page).to have_content(I18n.t("advertising_orders.replace_clip.duration_warning"))

    select "triumph-v2.png (15s)", from: "media_asset_id"
    click_button I18n.t("advertising_orders.replace_clip.submit")

    expect(page).to have_content(I18n.t("advertising_orders.replace_clip.replaced"))
    expect(page).to have_content(I18n.t("advertising_orders.show.document_version", version: 2))
    expect(order.reload.document_version).to eq(2)
    expect(order.media_plans.sole.id).to eq(plan_id)

    package = Agent::PackageBuilder.call(station: group.screens.first.station, now: Time.current)
    expect(package[:items].sole.dig(:rotation, :items).map { |item| item.dig(:media, :id) })
      .to eq([ replacement.id ])
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
