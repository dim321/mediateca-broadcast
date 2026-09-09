# frozen_string_literal: true

module Advertising
  class ActivateOrder < BaseService
    OccupiedWindow = Data.define(:line, :starts_at, :ends_at, :plan)
    ConflictedWindow = Data.define(:line, :starts_at, :ends_at, :error)
    Result = Data.define(:occupied_windows, :conflicted_windows, :quota_exceeded)

    def initialize(order:)
      @order = order
    end

    def call
      raise Error, I18n.t("advertising.errors.clip_not_ready") unless order.media_asset.reload.broadcast_ready?

      occupied = []
      conflicted = []

      order.advertising_order_lines.includes(:advertising_order_line_days, :screen).find_each do |line|
        occupy_line(line).each do |window|
          if window.is_a?(OccupiedWindow)
            occupied << window
          else
            conflicted << window
          end
        end
      end

      order.active! if occupied.any? && order.draft?
      Result.new(
        occupied_windows: occupied,
        conflicted_windows: conflicted,
        quota_exceeded: quota_exceeded?(occupied)
      )
    end

    private

    attr_reader :order

    def occupy_line(line)
      days_to_occupy(line).flat_map do |day|
        ScreenDayHours.call(
          screen: line.screen,
          date: day.date,
          windows: order.advertising_order_windows,
          time_zone: time_zone
        ).ranges.map { |starts_at, ends_at| occupy_range(line, starts_at, ends_at) }
      end
    end

    def days_to_occupy(line)
      line.advertising_order_line_days.sort_by(&:date).reject do |day|
        day.shows <= 0 || Coverage.occupied?(line: line, date: day.date, time_zone: time_zone)
      end
    end

    def occupy_range(line, starts_at, ends_at)
      plan = Airtime::OccupyWithPlan.call(
        organization: order.organization,
        rotation: order.rotation,
        starts_at: starts_at,
        ends_at: ends_at,
        placement_kind: order.placement_kind,
        shows_per_hour: order.shows_per_hour,
        screens: [ line.screen ],
        order_claim: true,
        advertising_order_line: line
      )
      OccupiedWindow.new(line: line, starts_at: plan.starts_at, ends_at: plan.ends_at, plan: plan)
    rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError, ActiveRecord::RecordInvalid => e
      ConflictedWindow.new(line: line, starts_at: starts_at, ends_at: ends_at, error: e.message)
    end

    def quota_exceeded?(occupied)
      occupied.any? { |window| CommercialQuota::Check.call(plan: window.plan).exceeded }
    end

    def time_zone
      order.organization.time_zone
    end
  end
end
