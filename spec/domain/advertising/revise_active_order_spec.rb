# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ReviseActiveOrder do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, :client, time_zone: "UTC") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }
  let(:screen) { group.screens.first }

  before do
    create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    screen.station.update!(offline_cache_hours: 72)
  end

  def active_order!(dates:)
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Triumph",
      shows_per_hour: 3
    )
    fill_order_grid!(order, screen: screen, dates: dates, shows: 9)
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  def revise(order, **overrides)
    described_class.call({
      order: order,
      shows_per_hour: 3,
      distribution_strategy: order.distribution_strategy,
      windows: [ { starts_at: "09:00", ends_at: "12:00" } ],
      screen_ids: [ screen.id ],
      lines: [ {
        screen_id: screen.id,
        days: order.advertising_order_line_days.map do |day|
          { date: day.date, skipped: false, shows: day.shows }
        end
      } ],
      grid_from: order.advertising_order_line_days.map(&:date).min,
      grid_to: order.advertising_order_line_days.map(&:date).max,
      product_name: order.product_name,
      placement_kind: order.placement_kind
    }.merge(overrides))
  end

  it "rejects a draft before writing" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = Advertising::CreateOrder.call(
        organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
      )
      fill_order_grid!(order, screen: screen, dates: [ Date.new(2026, 6, 5) ], shows: 9)

      expect { revise(order) }.to raise_error(Advertising::Error, I18n.t("advertising.errors.order_not_revisable"))
      expect(order.reload).to be_draft
    end
  end

  it "rejects an end date later than the stored grid" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

      expect {
        revise(order, grid_to: Date.new(2026, 6, 7), lines: [ {
          screen_id: screen.id,
          days: [
            { date: Date.new(2026, 6, 3), skipped: false, shows: 9 },
            { date: Date.new(2026, 6, 6), skipped: false, shows: 9 },
            { date: Date.new(2026, 6, 7), skipped: false, shows: 9 }
          ]
        } ])
      }.to raise_error(Advertising::Error, I18n.t("advertising.errors.end_date_extended"))

      expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(Date.new(2026, 6, 3), Date.new(2026, 6, 6))
      expect(order.media_plans.active.count).to eq(2)
    end
  end

  it "rejects a changed grid start" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

      expect {
        revise(order, grid_from: Date.new(2026, 6, 4))
      }.to raise_error(Advertising::Error, I18n.t("advertising.errors.start_date_changed"))
    end
  end

  it "rejects a tampered day on or before today" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])

      expect {
        revise(order, lines: [ {
          screen_id: screen.id,
          days: [
            { date: Date.new(2026, 6, 3), skipped: true, shows: 0 },
            { date: Date.new(2026, 6, 4), skipped: false, shows: 9 },
            { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
          ]
        } ])
      }.to raise_error(Advertising::Error, I18n.t("advertising.errors.locked_day_changed"))

      expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
    end
  end

  it "rejects a changed product name" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 6) ])

      expect {
        revise(order, product_name: "Other")
      }.to raise_error(Advertising::Error, I18n.t("advertising.errors.frozen_field_changed"))
    end
  end

  it "rejects a frequency outside the portrait intersection" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 6) ])

      expect { revise(order, shows_per_hour: 12) }.to raise_error(Advertising::InvalidGrid)
      expect(order.reload.shows_per_hour).to eq(3)
    end
  end

  it "rejects dropping a start date that is still in the future" do
    travel_to Time.utc(2026, 6, 1, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 5), Date.new(2026, 6, 6) ])

      expect {
        revise(order, lines: [ {
          screen_id: screen.id,
          days: [
            { date: Date.new(2026, 6, 4), skipped: false, shows: 9 },
            { date: Date.new(2026, 6, 5), skipped: false, shows: 9 },
            { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
          ]
        } ])
      }.to raise_error(Advertising::Error, I18n.t("advertising.errors.future_start_removed"))

      expect(order.media_plans.active.count).to eq(4)
    end
  end

  it "updates shows per hour only on future plans and line days" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])

      expect {
        revise(order, shows_per_hour: 6)
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(screen.station_id, "2026-06-06")

      order.reload
      expect(order.shows_per_hour).to eq(6)
      expect(order.document_version).to eq(2)
      expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 6)).shows).to eq(18)
      expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
      expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 4)).shows).to eq(9)
      future = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 6) }
      today_plan = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 4) }
      expect(future.shows_per_hour).to eq(6)
      expect(today_plan.shows_per_hour).to eq(3)
      expect(future.starts_at).to eq(Time.utc(2026, 6, 6, 9, 0, 0))
    end
  end

  it "does not bump the document or enqueue regen when nothing changed" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 6) ])

      expect { revise(order) }.not_to have_enqueued_job(Playlists::GenerateForDateJob)

      expect(order.reload.document_version).to eq(1)
    end
  end

  it "cancels a removed future day and keeps the order active" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

      revise(order, grid_to: Date.new(2026, 6, 3), lines: [ {
        screen_id: screen.id,
        days: [ { date: Date.new(2026, 6, 3), skipped: false, shows: 9 } ]
      } ])

      expect(order.reload).to be_active
      expect(order.advertising_order_line_days.map(&:date)).to eq([ Date.new(2026, 6, 3) ])
      expect(order.media_plans.active.count).to eq(1)
      expect(order.media_plans.cancelled.count).to eq(1)
    end
  end

  it "occupies a future day that was skipped" do
    travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
      order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

      revise(order, lines: [ {
        screen_id: screen.id,
        days: [
          { date: Date.new(2026, 6, 3), skipped: false, shows: 9 },
          { date: Date.new(2026, 6, 5), skipped: false, shows: 9 },
          { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
        ]
      } ])

      expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(
        Date.new(2026, 6, 3), Date.new(2026, 6, 5), Date.new(2026, 6, 6)
      )
      expect(order.media_plans.active.count).to eq(3)
    end
  end
end
