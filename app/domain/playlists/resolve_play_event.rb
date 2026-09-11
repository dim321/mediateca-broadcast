# frozen_string_literal: true

module Playlists
  class ResolvePlayEvent < BaseService
    Result = Data.define(:organization, :media_asset)

    def initialize(station:, screen:, media_asset_id:, now: Time.current)
      @station = station
      @screen = screen
      @media_asset_id = media_asset_id
      @now = now
    end

    def call
      if current_playlist_in_horizon?
        from_playlist
      else
        from_legacy_plan
      end
    end

    private

    attr_reader :station, :screen, :media_asset_id, :now

    def current_playlist_in_horizon?
      station.playlists.current.where(for_date: EnqueueRegen.horizon_dates(station)).exists?
    end

    def from_playlist
      item = PlaylistItem
        .joins(:playlist, :playlist_item_screens)
        .includes(:media_asset, media_plan: :airtime_booking)
        .where(playlists: { station_id: station.id })
        .where(playlist_item_screens: { screen_id: screen.id })
        .where(media_asset_id: media_asset_id)
        .where(
          "playlists.status = ? OR (playlists.status = ? AND playlists.generated_at >= ?)",
          Playlist.statuses.fetch("current"),
          Playlist.statuses.fetch("superseded"),
          2.hours.ago
        )
        .order(Arel.sql("CASE WHEN playlists.status = 'current' THEN 0 ELSE 1 END"), "playlists.generated_at DESC")
        .first
      return if item.nil?

      Result.new(organization: organization_for(item), media_asset: item.media_asset)
    end

    def organization_for(item)
      if item.media_plan?
        plan = item.media_plan
        return plan.organization if plan&.active? && plan.airtime_booking&.confirmed?
      end

      Organization.operator.first!
    end

    def from_legacy_plan
      horizon = now + station.offline_cache_hours.hours
      media_plan = MediaPlan
        .joins(broadcast_point_group: :screens, rotation: :rotation_items)
        .where(screens: { id: screen.id })
        .where(rotation_items: { media_asset_id: media_asset_id })
        .where("media_plans.starts_at <= ? AND media_plans.ends_at >= ?", horizon, now)
        .distinct
        .first
      return if media_plan.nil?

      Result.new(
        organization: media_plan.organization,
        media_asset: media_plan.rotation.media_assets.find(media_asset_id)
      )
    end
  end
end
