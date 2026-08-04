# frozen_string_literal: true

module Agent
  class PackageBuilder < BaseService
    def initialize(station:, now: Time.current)
      @station = station
      @now = now
    end

    def call
      package_items = items
      manifest = {
        items: package_items,
        screen_map: screen_map(package_items)
      }
      etag = Digest::SHA256.hexdigest(JSON.generate(manifest))

      manifest.merge(
        generated_at: now.iso8601,
        valid_until: horizon.iso8601,
        version: etag,
        etag:
      )
    end

    private

    attr_reader :station, :now

    def horizon
      now + station.offline_cache_hours.hours
    end

    def items
      media_plans.filter_map { |media_plan| plan_payload(media_plan) }
    end

    def media_plans
      MediaPlan
        .joins(broadcast_point_group: :screens)
        .where(screens: { station_id: station.id })
        .where("media_plans.starts_at <= ? AND media_plans.ends_at >= ?", horizon, now)
        .includes(
          broadcast_point_group: :screens,
          rotation: { rotation_items: { media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ] } }
        )
        .distinct
        .order(:starts_at, :id)
    end

    def plan_payload(media_plan)
      rotation_items = media_plan.rotation.ordered_items.filter_map { |item| media_payload(item) }
      return if rotation_items.empty?

      {
        media_plan_id: media_plan.id,
        starts_at: media_plan.starts_at.iso8601,
        ends_at: media_plan.ends_at.iso8601,
        screen_ids: station_screen_ids(media_plan),
        rotation: {
          id: media_plan.rotation_id,
          name: media_plan.rotation.name,
          items: rotation_items
        }
      }
    end

    def station_screen_ids(media_plan)
      media_plan.broadcast_point_group.screens
        .select { |screen| screen.station_id == station.id }
        .sort_by(&:id)
        .map(&:id)
    end

    def media_payload(rotation_item)
      media_asset = rotation_item.media_asset
      attachment = media_asset.broadcast_delivery_attachment
      return unless attachment

      {
        position: rotation_item.position,
        display_duration_seconds: rotation_item.display_duration_seconds,
        media: {
          id: media_asset.id,
          url: signed_blob_path(attachment),
          mime_type: attachment.blob.content_type
        }
      }
    end

    def signed_blob_path(attachment)
      Rails.application.routes.url_helpers.rails_blob_path(
        attachment,
        disposition: "inline",
        only_path: true
      )
    end

    def screen_map(package_items)
      package_items.each_with_object({}) do |item, map|
        item[:screen_ids].each { |screen_id| (map[screen_id.to_s] ||= []) << item[:media_plan_id] }
      end
    end
  end
end
