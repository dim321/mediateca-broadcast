# frozen_string_literal: true

module PlaylistGeneration
  WEDNESDAY = Date.new(2026, 9, 2)
  KRASNOYARSK_WED_HOURS = { "wed" => [ { "start" => "09:00", "end" => "21:00" } ] }.freeze
  BERLIN_SUN_HOURS = { "sun" => [ { "start" => "00:00", "end" => "06:00" } ] }.freeze

  def create_playlist_station!(time_zone: "Asia/Krasnoyarsk", hours: KRASNOYARSK_WED_HOURS)
    location = create(:location, time_zone: time_zone, operating_hours: hours)
    create(:station, location: location)
  end

  def create_clip_rotation!(organization:, count: 1, duration: 10)
    rotation = create(:rotation, organization: organization)
    count.times do
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset, display_duration_seconds: duration)
    end
    rotation
  end

  def create_cyclic_portrait!(station, filler_rotation:, frequency: 4, max_commercial_in_row: 3,
    insertion_time: nil, insertion_rotation: nil, header_start_rotation: nil, header_end_rotation: nil)
    screens = station.screens.sort_by(&:id)
    screens = [ create(:screen, station: station) ] if screens.empty?
    portraits = screens.map do |screen|
      build_cyclic_portrait_for_screen!(
        screen,
        filler_rotation: filler_rotation,
        frequency: frequency,
        max_commercial_in_row: max_commercial_in_row,
        insertion_time: insertion_time,
        insertion_rotation: insertion_rotation,
        header_start_rotation: header_start_rotation,
        header_end_rotation: header_end_rotation
      )
    end
    portraits.first
  end

  def build_cyclic_portrait_for_screen!(screen, filler_rotation:, frequency:, max_commercial_in_row:,
    insertion_time:, insertion_rotation:, header_start_rotation:, header_end_rotation:)
    portrait = create(
      :broadcast_portrait,
      :for_screen,
      screen: screen,
      block_frequency_per_hour: frequency,
      max_commercial_in_row: max_commercial_in_row,
      neutral_min_seconds: 10
    )
    position = 1
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: position)
    position += 1
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, position: position,
      rotation: filler_rotation)
    if insertion_time
      position += 1
      create(
        :broadcast_portrait_block,
        :insertion,
        broadcast_portrait: portrait,
        position: position,
        rotation: insertion_rotation,
        time_of_day: insertion_time,
        pick_strategy: "sequential"
      )
    end
    if header_start_rotation
      position += 1
      create(:broadcast_portrait_block, :service_header_start, broadcast_portrait: portrait,
        position: position, rotation: header_start_rotation)
    end
    if header_end_rotation
      position += 1
      create(:broadcast_portrait_block, :service_header_end, broadcast_portrait: portrait,
        position: position, rotation: header_end_rotation)
    end
    portrait
  end

  def occupy_with_clips!(screen:, organization:, rotation:, starts_at:, ends_at:,
    placement_kind: :own_atmosphere, shows_per_hour: nil, group_organization: nil)
    group = create(:broadcast_point_group, organization: group_organization || organization)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: starts_at,
      ends_at: ends_at,
      placement_kind: placement_kind,
      shows_per_hour: shows_per_hour
    )
  end

  def items_at(playlist, offset)
    playlist.items.select { |item| item.offset_seconds == offset }
  end

  def source_kinds_at(playlist, offset)
    items_at(playlist, offset).map(&:source_kind)
  end

  def item_screen_ids(item)
    item.screens.map(&:id).sort
  end
end

RSpec.configure do |config|
  config.include PlaylistGeneration
end
