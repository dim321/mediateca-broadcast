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

      order.advertising_order_lines.includes(:advertising_order_line_days, :broadcast_point_group).find_each do |line|
        collapse(line).each do |chain, shows_per_hour|
          window = occupy_chain(line, chain, shows_per_hour)
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

    def collapse(line)
      days = line.advertising_order_line_days.sort_by(&:date).reject do |day|
        Coverage.occupied?(line: line, date: day.date, time_zone: time_zone)
      end
      return [] if days.empty?

      chains = []
      current = []
      current_rate = nil

      days.each do |day|
        hours = OperatingHours.call(group: line.broadcast_point_group, date: day.date, time_zone: time_zone)
        next if hours.zero?

        rate = day.shows / hours
        if current.empty?
          current = [ day ]
          current_rate = rate
        elsif day.date == current.last.date + 1 && rate == current_rate
          current << day
        else
          chains << [ current, current_rate ]
          current = [ day ]
          current_rate = rate
        end
      end
      chains << [ current, current_rate ] if current.any?
      chains
    end

    def occupy_chain(line, chain, shows_per_hour)
      starts_at, ends_at = bounds(chain.first.date, chain.last.date)
      begin
        plan = nil
        MediaPlan.transaction do
          plan = Airtime::OccupyWithPlan.call(
            organization: order.organization,
            broadcast_point_group: line.broadcast_point_group,
            rotation: order.rotation,
            starts_at: starts_at,
            ends_at: ends_at,
            placement_kind: order.placement_kind,
            shows_per_hour: shows_per_hour
          )
          plan.update_column(:advertising_order_line_id, line.id)
        end
        OccupiedWindow.new(line: line, starts_at: plan.starts_at, ends_at: plan.ends_at, plan: plan)
      rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError, ActiveRecord::RecordInvalid => e
        ConflictedWindow.new(line: line, starts_at: starts_at, ends_at: ends_at, error: e.message)
      end
    end

    def bounds(first_date, last_date)
      zone = Time.find_zone!(time_zone)
      starts = zone.local(first_date.year, first_date.month, first_date.day)
      ends = zone.local((last_date + 1).year, (last_date + 1).month, (last_date + 1).day)
      [ starts, ends ]
    end

    def quota_exceeded?(occupied)
      occupied.any? { |window| CommercialQuota::Check.call(plan: window.plan).exceeded }
    end

    def time_zone
      order.organization.time_zone
    end
  end
end
