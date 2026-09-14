# frozen_string_literal: true

module Playlists
  class Fingerprint < BaseService
    PICKER_VERSION = "v1"

    def initialize(station:, for_date:)
      @station = station
      @for_date = for_date.to_date
    end

    def call
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
    end

    def self.occupying_plans(station:, for_date:)
      zone = Time.find_zone!(station.location.time_zone)
      day_start = zone.local(for_date.year, for_date.month, for_date.day)
      day_end = zone.local((for_date + 1).year, (for_date + 1).month, (for_date + 1).day)
      screen_ids = station.screen_ids
      return [] if screen_ids.empty?

      MediaPlan
        .active
        .joins(:airtime_booking)
        .left_outer_joins(:media_plan_screens)
        .left_outer_joins(broadcast_point_group: :broadcast_point_group_memberships)
        .merge(AirtimeBooking.confirmed)
        .where(
          "media_plan_screens.screen_id IN (:ids) OR broadcast_point_group_memberships.screen_id IN (:ids)",
          ids: screen_ids
        )
        .where("media_plans.starts_at < ? AND media_plans.ends_at > ?", day_end, day_start)
        .where("airtime_bookings.starts_at <= media_plans.starts_at AND airtime_bookings.ends_at >= media_plans.ends_at")
        .includes(
          :airtime_booking,
          :media_plan_screens,
          rotation: { rotation_items: { media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ] } },
          broadcast_point_group: :screens
        )
        .distinct
        .order(:id)
        .to_a
    end

    private

    attr_reader :station, :for_date

    def payload
      {
        picker_algorithm: PICKER_VERSION,
        location: {
          time_zone: station.location.time_zone
        },
        screens: screens_payload,
        occupying_plans: occupying_plans.map { |plan| plan_payload(plan) },
        rotation_items: rotation_item_payloads
      }
    end

    def screens_payload
      station.screens.order(:id).includes(:broadcast_portrait).map do |screen|
        {
          id: screen.id,
          effective_operating_hours: screen.effective_operating_hours,
          portrait: portrait_payload(screen.broadcast_portrait)
        }
      end
    end

    def portrait_payload(portrait)
      return if portrait.nil?

      {
        id: portrait.id,
        updated_at: iso(portrait.updated_at),
        block_frequencies_per_hour: portrait.block_frequencies_per_hour,
        max_commercial_in_row: portrait.max_commercial_in_row,
        neutral_min_seconds: portrait.neutral_min_seconds,
        blocks: portrait.blocks.sort_by(&:position).map { |block| block_payload(block) }
      }
    end

    def block_payload(block)
      {
        position: block.position,
        kind: block.kind,
        rotation_id: block.rotation_id,
        pick_strategy: block.pick_strategy,
        time_of_day: format_time_of_day(block.time_of_day)
      }
    end

    def occupying_plans
      @occupying_plans ||= self.class.occupying_plans(station: station, for_date: for_date)
    end

    def plan_payload(plan)
      {
        id: plan.id,
        updated_at: iso(plan.updated_at),
        starts_at: iso(plan.starts_at),
        ends_at: iso(plan.ends_at),
        shows_per_hour: plan.shows_per_hour,
        placement_kind: plan.placement_kind,
        rotation_id: plan.rotation_id
      }
    end

    def rotation_item_payloads
      rotation_ids = (screen_rotation_ids + occupying_plans.map(&:rotation_id)).uniq
      return [] if rotation_ids.empty?

      RotationItem.where(rotation_id: rotation_ids).order(:rotation_id, :position, :id).map do |item|
        {
          id: item.id,
          position: item.position,
          media_asset_id: item.media_asset_id,
          display_duration_seconds: item.display_duration_seconds,
          updated_at: iso(item.updated_at)
        }
      end
    end

    def screen_rotation_ids
      station.screens.includes(broadcast_portrait: :blocks).flat_map do |screen|
        Array(screen.broadcast_portrait&.blocks).filter_map(&:rotation_id)
      end
    end

    def format_time_of_day(value)
      value&.strftime("%H:%M")
    end

    def iso(value)
      value&.utc&.iso8601(6)
    end

    def canonicalize(value)
      case value
      when Hash
        value.stringify_keys.sort.to_h.transform_values { |item| canonicalize(item) }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end
  end
end
