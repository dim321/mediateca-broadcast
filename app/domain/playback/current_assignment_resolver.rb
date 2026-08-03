# frozen_string_literal: true

module Playback
  class CurrentAssignmentResolver
    def self.call(broadcast_point:, at: Time.current)
      new(broadcast_point:, at:).call
    end

    def initialize(broadcast_point:, at:)
      @broadcast_point = broadcast_point
      @at = at
    end

    def call
      rule = active_rule
      return nil unless rule

      {
        assignment_id: rule.id,
        starts_at: rule.starts_at.iso8601,
        ends_at: rule.ends_at.iso8601,
        # Keep the Device API contract stable while Agent clients migrate to rotation terminology.
        playlist: {
          id: rule.rotation_id,
          items: rotation_items(rule).map { |item| serialize_item(item) }
        }
      }
    end

    private

    attr_reader :broadcast_point, :at

    def active_rule
      ScheduleRule
        .joins(schedule_targets: { point_group: :point_group_memberships })
        .where(point_group_memberships: { broadcast_point_id: broadcast_point.id })
        .where("schedule_rules.starts_at <= ? AND schedule_rules.ends_at > ?", at, at)
        .includes(rotation: { rotation_items: { media_asset: [ :file_attachment, :file_blob ] } })
        .order(starts_at: :asc)
        .distinct
        .first
    end

    def rotation_items(rule)
      rule.rotation.rotation_items
        .includes(media_asset: [ :file_attachment, :file_blob ])
        .order(:position)
    end

    def serialize_item(item)
      media_asset = item.media_asset

      {
        position: item.position,
        kind: media_asset.content_kind,
        duration_seconds: item.display_duration_seconds || media_asset.duration_seconds,
        media: Playback::MediaUrlPresenter.call(media_asset)
      }
    end
  end
end
