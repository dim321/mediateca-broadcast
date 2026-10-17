# frozen_string_literal: true

module Agent
  class ScreenTimelines < BaseService
    Result = Data.define(:complete, :digests_by_screen_id)

    def initialize(station:)
      @station = station
    end

    def call
      dates = Playlists::EnqueueRegen.horizon_dates(station)
      playlists = load_playlists(dates)
      Result.new(
        complete: dates.all? { |date| playlists.any? { |playlist| playlist.for_date == date } },
        digests_by_screen_id: digests_for(playlists)
      )
    end

    private

    attr_reader :station

    def load_playlists(dates)
      station.playlists.current.where(for_date: dates)
        .includes(items: [ :screens, { media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ] } ])
        .order(:for_date, :id)
        .to_a
    end

    def digests_for(playlists)
      station.screens.select { |screen| ScreenWiring.wired?(screen) }.each_with_object({}) do |screen, digests|
        digest = digest_for(slots_for(screen, playlists))
        digests[screen.id] = digest if digest
      end
    end

    def slots_for(screen, playlists)
      playlists.flat_map { |playlist| slots_from(playlist, screen) }
        .sort_by { |slot| [ slot[:for_date], slot[:offset_seconds], slot[:media_id], slot[:duration_seconds], slot[:starts_at].to_s ] }
    end

    def slots_from(playlist, screen)
      playlist.items.sort_by(&:position).filter_map do |item|
        next unless item.screens.any? { |candidate| candidate.id == screen.id }
        next unless item.media_asset.broadcast_delivery_attachment

        anchor = playlist.broadcast_day_starts_at
        starts_at = anchor + item.offset_seconds.seconds if anchor
        {
          for_date: playlist.for_date.iso8601,
          offset_seconds: item.offset_seconds,
          starts_at: starts_at&.iso8601,
          duration_seconds: item.duration_seconds,
          media_id: item.media_asset_id
        }
      end
    end

    def digest_for(slots)
      return if slots.empty?

      Digest::SHA256.hexdigest(JSON.generate(slots))
    end
  end
end
