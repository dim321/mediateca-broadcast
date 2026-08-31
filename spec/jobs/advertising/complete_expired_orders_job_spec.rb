# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::CompleteExpiredOrdersJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  def active_order_with_dates(organization:, dates:)
    order = create(:advertising_order, organization: organization, status: :active)
    line = create(:advertising_order_line, advertising_order: order)
    dates.each do |date|
      create(:advertising_order_line_day, advertising_order_line: line, date: date, shows: 36)
    end
    order
  end

  it "marks an active order completed when every date is in the past in the organization TZ" do
    organization = create(:organization, :client, time_zone: "UTC")
    order = active_order_with_dates(organization: organization, dates: [ Date.new(2026, 8, 29), Date.new(2026, 8, 30) ])

    travel_to Time.utc(2026, 8, 31, 12, 0, 0) do
      described_class.perform_now
    end

    expect(order.reload).to be_completed
  end

  it "leaves an active order active when any date is today or later in the organization TZ" do
    organization = create(:organization, :client, time_zone: "UTC")
    order = active_order_with_dates(organization: organization, dates: [ Date.new(2026, 8, 30), Date.new(2026, 8, 31) ])

    travel_to Time.utc(2026, 8, 31, 12, 0, 0) do
      described_class.perform_now
    end

    expect(order.reload).to be_active
  end

  it "uses the organization time zone, not UTC, to decide whether dates are in the past" do
    kamchatka = create(:organization, :client, time_zone: "Asia/Kamchatka")
    utc_org = create(:organization, :client, time_zone: "UTC")
    kamchatka_order = active_order_with_dates(organization: kamchatka, dates: [ Date.new(2026, 8, 31) ])
    utc_order = active_order_with_dates(organization: utc_org, dates: [ Date.new(2026, 8, 31) ])

    # 2026-08-31 16:00 UTC == 2026-09-01 04:00 in Asia/Kamchatka (UTC+12)
    travel_to Time.utc(2026, 8, 31, 16, 0, 0) do
      described_class.perform_now
    end

    expect(kamchatka_order.reload).to be_completed
    expect(utc_order.reload).to be_active
  end

  it "does not complete draft, cancelled, or dateless active orders" do
    organization = create(:organization, :client, time_zone: "UTC")
    draft = create(:advertising_order, organization: organization, status: :draft)
    cancelled = create(:advertising_order, organization: organization, status: :cancelled)
    dateless = create(:advertising_order, organization: organization, status: :active)
    create(:advertising_order_line, advertising_order: dateless)

    travel_to Time.utc(2026, 8, 31, 12, 0, 0) do
      described_class.perform_now
    end

    expect(draft.reload).to be_draft
    expect(cancelled.reload).to be_cancelled
    expect(dateless.reload).to be_active
  end

  it "is idempotent when an order is already completed" do
    organization = create(:organization, :client, time_zone: "UTC")
    order = active_order_with_dates(organization: organization, dates: [ Date.new(2026, 8, 30) ])

    travel_to Time.utc(2026, 8, 31, 12, 0, 0) do
      described_class.perform_now
      described_class.perform_now
    end

    expect(order.reload).to be_completed
  end

  it "is registered as a nightly production recurring job" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    entry = config.fetch("production").fetch("complete_expired_advertising_orders")

    expect(entry.fetch("class")).to eq("Advertising::CompleteExpiredOrdersJob")
    expect(entry.fetch("schedule")).to match(/every day/i)
  end
end
