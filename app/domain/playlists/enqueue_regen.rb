# frozen_string_literal: true

module Playlists
  class EnqueueRegen < BaseService
    def initialize(station_ids:, dates:)
      @station_ids = Array(station_ids)
      @dates = Array(dates)
    end

    def call
      pairs = []
      Station.where(id: station_ids).includes(:location).find_each do |station|
        allowed = self.class.horizon_dates(station)
        dates.map { |date| date.to_date }.uniq.each do |date|
          next unless allowed.include?(date)

          pairs << [ station.id, date ]
        end
      end

      pairs.uniq.each do |station_id, date|
        GenerateForDateJob.perform_later(station_id, date.iso8601)
      end
    end

    def self.from_plan(plan)
      return if plan.blank?

      from_group_window(group: plan.broadcast_point_group, starts_at: plan.starts_at, ends_at: plan.ends_at)
    end

    def self.from_group_window(group:, starts_at:, ends_at:)
      return if group.blank?

      stations = group.screens.includes(station: :location).filter_map(&:station).uniq
      stations.each do |station|
        call(station_ids: [ station.id ], dates: overlapping_dates(station, starts_at, ends_at))
      end
    end

    def self.from_station(station)
      return if station.blank?

      call(station_ids: [ station.id ], dates: horizon_dates(station))
    end

    def self.from_location(location)
      return if location.blank?

      location.stations.includes(:location).find_each { from_station(it) }
    end

    def self.from_screen(screen)
      from_station(screen&.station)
    end

    def self.from_rotation(rotation)
      return if rotation.blank?

      portrait_station_ids = BroadcastPortraitBlock.where(rotation_id: rotation.id)
        .joins(:broadcast_portrait)
        .where.not(broadcast_portraits: { station_id: nil })
        .distinct
        .pluck("broadcast_portraits.station_id")
      Station.where(id: portrait_station_ids).includes(:location).find_each { from_station(it) }

      rotation.media_plans.active.includes(broadcast_point_group: { screens: { station: :location } }).find_each do |plan|
        from_plan(plan)
      end
    end

    def self.horizon_dates(station)
      today = Time.current.in_time_zone(station.location.time_zone).to_date
      span = (station.offline_cache_hours.to_f / 24.0).ceil
      (today..(today + span)).to_a
    end

    def self.overlapping_dates(station, starts_at, ends_at)
      zone = Time.find_zone!(station.location.time_zone)
      start_date = starts_at.in_time_zone(zone).to_date
      end_time = ends_at.in_time_zone(zone)
      end_date = if end_time == end_time.beginning_of_day
        end_time.to_date - 1
      else
        end_time.to_date
      end
      return [] if end_date < start_date

      (start_date..end_date).to_a
    end

    private

    attr_reader :station_ids, :dates
  end
end
