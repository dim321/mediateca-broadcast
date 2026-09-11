# frozen_string_literal: true

module Playlists
  class PackageFromPlaylists < BaseService
    def initialize(station:, now: Time.current)
      @station = station
      @now = now
    end

    def call
      dates = EnqueueRegen.horizon_dates(station)
      playlists = load_playlists(dates)
      missing = dates - playlists.map(&:for_date)
      EnqueueRegen.call(station_ids: [ station.id ], dates: missing) if missing.any?

      entries = playlists.flat_map { |playlist| entries_for(playlist) }
      etag = Digest::SHA256.hexdigest(JSON.generate(etag_payload(entries)))

      {
        version: etag,
        etag: etag,
        generated_at: now.iso8601,
        valid_until: (now + station.offline_cache_hours.hours).iso8601,
        entries: entries,
        screen_map: screen_map(entries)
      }
    end

    private

    attr_reader :station, :now

    def load_playlists(dates)
      station.playlists.current.where(for_date: dates)
        .includes(items: [ :screens, { media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ] } ])
        .order(:for_date, :id)
        .to_a
    end

    def entries_for(playlist)
      playlist.items.sort_by(&:position).filter_map { |item| entry_payload(playlist, item) }
    end

    def entry_payload(playlist, item)
      attachment = item.media_asset.broadcast_delivery_attachment
      return unless attachment

      anchor = playlist.broadcast_day_starts_at
      starts_at = anchor + item.offset_seconds.seconds if anchor

      {
        for_date: playlist.for_date.iso8601,
        broadcast_day_starts_at: anchor&.iso8601,
        position: item.position,
        offset_seconds: item.offset_seconds,
        starts_at: starts_at&.iso8601,
        duration_seconds: item.duration_seconds,
        source_kind: item.source_kind,
        media_plan_id: item.media_plan_id,
        screen_ids: item.screens.map(&:id).sort,
        media: {
          id: item.media_asset_id,
          url: signed_blob_path(attachment),
          mime_type: attachment.blob.content_type
        }
      }
    end

    def etag_payload(entries)
      entries.map do |entry|
        entry.slice(
          :for_date, :broadcast_day_starts_at, :position, :offset_seconds, :starts_at,
          :duration_seconds, :source_kind, :media_plan_id, :screen_ids, :media
        )
      end
    end

    def screen_map(entries)
      entries.each_with_index.with_object({}) do |(entry, index), map|
        entry[:screen_ids].each { |screen_id| (map[screen_id.to_s] ||= []) << index }
      end
    end

    def signed_blob_path(attachment)
      Rails.application.routes.url_helpers.rails_blob_path(
        attachment,
        disposition: "inline",
        only_path: true
      )
    end
  end
end
