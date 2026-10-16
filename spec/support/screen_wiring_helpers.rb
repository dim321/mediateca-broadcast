# frozen_string_literal: true

module ScreenWiringHelpers
  HORIZON_DAY = Date.new(2026, 10, 16)

  def wiring_time
    Time.utc(2026, 10, 16, 6, 0, 0)
  end

  def wiring_station
    location = create(:location, time_zone: "UTC")
    create(:station, location:, offline_cache_hours: 24)
  end

  def wired_screen(station, ip:, mac: "78:53:33:4b:2c:29", **attributes)
    create(
      :screen,
      station:,
      network_registered: true,
      ip_address: ip,
      mac_address: mac,
      **attributes
    )
  end

  def horizon_playlist(station, for_date, anchor_hour: 2)
    station.playlists.current.find_by(for_date:) || create(
      :playlist,
      station:,
      for_date:,
      broadcast_day_starts_at: Time.utc(for_date.year, for_date.month, for_date.day, anchor_hour, 0, 0)
    )
  end

  def cover_horizon(station)
    [ HORIZON_DAY, HORIZON_DAY + 1 ].map { |date| horizon_playlist(station, date) }
  end

  def add_slot(playlist, screen, asset:, offset_seconds: 0, duration_seconds: 10, source_kind: "filler")
    position = playlist.items.maximum(:position).to_i + 1
    create(
      :playlist_item,
      playlist:,
      media_asset: asset,
      position:,
      offset_seconds:,
      duration_seconds:,
      source_kind:
    ).tap do |item|
      item.screens = [ screen ]
      item.save!
    end
  end

  def cover_horizon_with_slot(station, screen, asset:, offset_seconds: 0, duration_seconds: 10)
    cover_horizon(station).map do |playlist|
      add_slot(playlist, screen, asset:, offset_seconds:, duration_seconds:)
      playlist
    end
  end
end

# Ruby 4 evaluates RSpec groups via module_exec with empty constant nesting,
# so a constant on an included module is invisible inside examples.
HORIZON_DAY = ScreenWiringHelpers::HORIZON_DAY

RSpec.configure do |config|
  config.include ScreenWiringHelpers
end
