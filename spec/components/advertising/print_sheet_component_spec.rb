# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::PrintSheetComponent, type: :component do
  let(:organization) { create(:organization, :client, name: "Triumph LLC") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization, name: "Storefronts") }

  def order_with_days(dates:, shows: 36, discount_cents: 0)
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_asset: asset,
      product_name: "Triumph",
      discount_cents: discount_cents
    )
    Advertising::UpdateGrid.call(
      order: order,
      lines: [ {
        broadcast_point_group_id: group.id,
        price_per_day_cents: 34_020_00,
        days: dates.map { |date| { date: date, shows: shows } }
      } ]
    )
    order.reload
  end

  it "renders dashes for days without placement inside a block" do
    order = order_with_days(
      dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5) ],
      shows: 12
    )

    render_inline(described_class.new(order: order))

    expect(page).to have_css(".print-sheet__cell", text: "—", minimum: 1)
    expect(page).to have_css(".print-sheet__cell", text: "12", count: 2)
  end

  it "renders two month blocks for December–January when the span exceeds 31 days (AE9)" do
    dates = (Date.new(2026, 12, 25)..Date.new(2027, 1, 31)).to_a
    order = order_with_days(dates: dates)

    render_inline(described_class.new(order: order))

    expect(page).to have_css(".print-sheet__block-title", count: 2)
    expect(page).to have_content(I18n.l(Date.new(2026, 12, 1), format: "%B %Y"))
    expect(page).to have_content(I18n.l(Date.new(2027, 1, 1), format: "%B %Y"))
  end

  it "renders one block for a 20-day cross-month span (AE9)" do
    dates = (Date.new(2026, 12, 15)..Date.new(2027, 1, 3)).to_a
    order = order_with_days(dates: dates)

    render_inline(described_class.new(order: order))

    expect(page).to have_css(".print-sheet__block-title", count: 1)
  end

  it "renders header, totals, discount, and signatures" do
    order = order_with_days(
      dates: [ Date.new(2026, 6, 3) ],
      shows: 36,
      discount_cents: 5_000_00
    )

    render_inline(described_class.new(order: order))

    expect(page).to have_content("Triumph LLC")
    expect(page).to have_content("Triumph")
    expect(page).to have_content(I18n.t("advertising.print_sheet.total_with_discount"))
    expect(page).to have_content(I18n.t("advertising.print_sheet.subtotal"))
    expect(page).to have_content(I18n.t("advertising.print_sheet.manager_signature"))
    expect(page).to have_content(I18n.t("advertising.print_sheet.client_signature"))
    expect(page).to have_content(I18n.t("advertising.print_sheet.document_version", version: 1))
  end
end
