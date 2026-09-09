# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::GenerateForDate do
  def generate!(station, for_date = PlaylistGeneration::WEDNESDAY)
    described_class.call(station: station, for_date: for_date)
  end

  def krasnoyarsk
    Time.find_zone!("Asia/Krasnoyarsk")
  end

  def local_slot(hour, min = 0, date: PlaylistGeneration::WEDNESDAY)
    krasnoyarsk.local(date.year, date.month, date.day, hour, min, 0)
  end

  it "skips persist when the station has no portrait and no default template" do
    station = create_playlist_station!

    result = generate!(station)

    expect(result.playlist).to be_nil
    expect(result.skipped).to eq(:missing_portrait)
    expect(result.warnings).to eq([])
    expect(Playlist.where(station: station, for_date: PlaylistGeneration::WEDNESDAY)).to be_empty
  end

  it "copies the default template then generates (R10)" do
    filler = create_clip_rotation!(organization: create(:organization, :client))
    template = create(:broadcast_portrait, :default)
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: template, position: 1)
    create(:broadcast_portrait_block, :filler, broadcast_portrait: template, position: 2, rotation: filler)
    station = create_playlist_station!
    create(:screen, station: station)

    result = generate!(station)

    expect(result.skipped).to be_nil
    expect(station.screens.first.reload.broadcast_portrait).to be_present
    expect(result.playlist).to be_current
  end

  it "anchors Krasnoyarsk 09:00–21:00 and interleaves filler with commercial (AE3)" do
    station = create_playlist_station!
    screen = create(:screen, station: station)
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    ads = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(station, filler_rotation: filler)
    occupy_with_clips!(
      screen: screen,
      organization: org,
      rotation: ads,
      starts_at: local_slot(9),
      ends_at: local_slot(21)
    )

    result = generate!(station)
    playlist = result.playlist

    expect(result.skipped).to be_nil
    expect(playlist.broadcast_day_starts_at).to eq(local_slot(9).utc)
    expect(playlist.items.minimum(:offset_seconds)).to eq(0)
    expect(playlist.items.maximum(:offset_seconds)).to be >= (11.hours + 45.minutes).to_i
    expect(source_kinds_at(playlist, 0)).to eq(%w[media_plan])
    expect(source_kinds_at(playlist, 900)).to eq(%w[filler])
  end

  it "keeps commercial clips on their own screens and shares filler (AE4)" do
    station = create_playlist_station!
    screen_a = create(:screen, station: station)
    screen_b = create(:screen, station: station)
    org_a = create(:organization, :client)
    org_b = create(:organization, :client)
    filler = create_clip_rotation!(organization: create(:organization, :client))
    create_cyclic_portrait!(station, filler_rotation: filler)
    plan_a = occupy_with_clips!(screen: screen_a, organization: org_a,
      rotation: create_clip_rotation!(organization: org_a), starts_at: local_slot(9), ends_at: local_slot(21))
    plan_b = occupy_with_clips!(screen: screen_b, organization: org_b,
      rotation: create_clip_rotation!(organization: org_b), starts_at: local_slot(9), ends_at: local_slot(21))

    playlist = generate!(station).playlist
    commercial = playlist.items.select(&:media_plan?)
    filler_items = playlist.items.select(&:filler?)

    expect(commercial.map(&:media_plan_id).uniq).to contain_exactly(plan_a.id, plan_b.id)
    expect(commercial.all? { |item| (item_screen_ids(item) - plan_a.broadcast_point_group.screen_ids).empty? ||
      (item_screen_ids(item) - plan_b.broadcast_point_group.screen_ids).empty? }).to be(true)
    expect(filler_items).to be_present
    expect(filler_items.map { |item| item_screen_ids(item) }).to all(eq([ screen_a.id, screen_b.id ].sort))
  end

  it "uses each screen's effective hours for slot offsets (AE4 hours)" do
    station = create_playlist_station!
    screen_a = create(:screen, station: station)
    screen_b = create(
      :screen,
      station: station,
      inherit_operating_hours_from_location: false,
      operating_hours: { "wed" => [ { "start" => "10:00", "end" => "20:00" } ] }
    )
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(station, filler_rotation: filler)

    playlist = generate!(station).playlist
    offsets_a = playlist.items.select { |item| item_screen_ids(item).include?(screen_a.id) }.map(&:offset_seconds)
    offsets_b = playlist.items.select { |item| item_screen_ids(item).include?(screen_b.id) }.map(&:offset_seconds)

    expect(playlist.broadcast_day_starts_at).to eq(local_slot(9).utc)
    expect(offsets_a.min).to eq(0)
    expect(offsets_b.min).to eq(1.hour.to_i)
    expect(offsets_a.max).to be > offsets_b.max
  end

  it "caps commercial clips by shows_per_hour and max_commercial_in_row (AE5)" do
    station = create_playlist_station!
    screen = create(:screen, station: station)
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    ads = create_clip_rotation!(organization: org, count: 4)
    create_cyclic_portrait!(station, filler_rotation: filler, max_commercial_in_row: 3)
    occupy_with_clips!(screen: screen, organization: org, rotation: ads,
      starts_at: local_slot(9), ends_at: local_slot(21), shows_per_hour: 2)

    kinds = generate!(station).playlist.items.sort_by(&:offset_seconds)
      .select { |item| item.offset_seconds < 3600 && item_screen_ids(item).include?(screen.id) }
      .map(&:source_kind)
    commercial_hour = kinds.count { |kind| kind == "media_plan" }
    max_run = kinds.chunk { |kind| kind == "media_plan" }.filter_map { |ok, run| run.size if ok }.max || 0

    expect(commercial_hour).to eq(2)
    expect(max_run).to be <= 3
  end

  it "mixes clips from two overlapping commercial order claims on the same screen" do
    station = create_playlist_station!
    screen = create(:screen, station: station)
    filler = create_clip_rotation!(organization: create(:organization, :client))
    create_cyclic_portrait!(station, filler_rotation: filler, frequency: 4, max_commercial_in_row: 3)

    first_org = create(:organization, :client)
    second_org = create(:organization, :client)
    first_ads = create_clip_rotation!(organization: first_org)
    second_ads = create_clip_rotation!(organization: second_org)
    occupy_order_claim!(
      screen: screen, organization: first_org, rotation: first_ads,
      starts_at: local_slot(9), ends_at: local_slot(21), shows_per_hour: 3
    )
    occupy_order_claim!(
      screen: screen, organization: second_org, rotation: second_ads,
      starts_at: local_slot(9), ends_at: local_slot(21), shows_per_hour: 3
    )

    hour = generate!(station).playlist.items.sort_by(&:offset_seconds).select do |item|
      item.offset_seconds < 3600 && item.media_plan? && item_screen_ids(item).include?(screen.id)
    end

    expect(hour.map(&:media_asset_id)).to include(
      first_ads.ordered_items.first.media_asset_id,
      second_ads.ordered_items.first.media_asset_id
    )
  end

  it "wraps mixed order-claim commercials with service headers once" do
    station = create_playlist_station!
    owner = create(:organization, :client)
    screen = create(:screen, station: station, owner_organization: owner)
    filler = create_clip_rotation!(organization: owner)
    start_rot = create_clip_rotation!(organization: owner)
    end_rot = create_clip_rotation!(organization: owner)
    create_cyclic_portrait!(
      station,
      filler_rotation: filler,
      header_start_rotation: start_rot,
      header_end_rotation: end_rot
    )
    first_org = create(:organization, :client)
    second_org = create(:organization, :client)
    occupy_order_claim!(
      screen: screen, organization: first_org,
      rotation: create_clip_rotation!(organization: first_org),
      starts_at: local_slot(9), ends_at: local_slot(21), shows_per_hour: 3
    )
    occupy_order_claim!(
      screen: screen, organization: second_org,
      rotation: create_clip_rotation!(organization: second_org),
      starts_at: local_slot(9), ends_at: local_slot(21), shows_per_hour: 3
    )

    first_slot = generate!(station).playlist.items.sort_by(&:offset_seconds).select do |item|
      item.offset_seconds < 900 && item_screen_ids(item).include?(screen.id)
    end
    kinds = first_slot.map(&:source_kind)

    expect(kinds.first).to eq("service")
    expect(kinds.last).to eq("service")
    expect(kinds.count("service")).to eq(2)
    expect(kinds.count("media_plan")).to eq(2)
    expect(first_slot.first.media_asset_id).to eq(start_rot.ordered_items.first.media_asset_id)
    expect(first_slot.last.media_asset_id).to eq(end_rot.ordered_items.first.media_asset_id)
  end

  it "lets a 12:00 insertion replace that slot without shifting later cyclic items (AE6)" do
    station = create_playlist_station!
    screen = create(:screen, station: station)
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    insertion = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(station, filler_rotation: filler,
      insertion_time: "12:00", insertion_rotation: insertion)
    occupy_with_clips!(screen: screen, organization: org,
      rotation: create_clip_rotation!(organization: org), starts_at: local_slot(9), ends_at: local_slot(21))

    playlist = generate!(station).playlist
    noon = 3.hours.to_i
    quarter = noon + 15.minutes.to_i

    expect(source_kinds_at(playlist, noon)).to eq(%w[insertion])
    expect(source_kinds_at(playlist, quarter)).to eq(%w[filler])
  end

  it "skips a spring-forward 02:30 insertion and keeps the first fall-back occurrence (AE8)" do
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    insertion = create_clip_rotation!(organization: org)
    spring_station = create_playlist_station!(time_zone: "Europe/Berlin", hours: PlaylistGeneration::BERLIN_SUN_HOURS)
    fall_station = create_playlist_station!(time_zone: "Europe/Berlin", hours: PlaylistGeneration::BERLIN_SUN_HOURS)
    create(:screen, station: spring_station)
    create(:screen, station: fall_station)
    create_cyclic_portrait!(spring_station, filler_rotation: filler,
      insertion_time: "02:30", insertion_rotation: insertion)
    create_cyclic_portrait!(fall_station, filler_rotation: filler,
      insertion_time: "02:30", insertion_rotation: insertion)

    spring = generate!(spring_station, Date.new(2026, 3, 29)).playlist
    fall = generate!(fall_station, Date.new(2026, 10, 25)).playlist

    expect(spring.items.count(&:insertion?)).to eq(0)
    expect(fall.items.count(&:insertion?)).to eq(1)
  end

  it "persists a current playlist with zero items on a closed weekday (AE10)" do
    station = create_playlist_station!(hours: { "mon" => [ { "start" => "09:00", "end" => "21:00" } ] })
    create(:screen, station: station)
    filler = create_clip_rotation!(organization: create(:organization, :client))
    create_cyclic_portrait!(station, filler_rotation: filler)

    result = generate!(station)
    playlist = result.playlist

    expect(result.skipped).to be_nil
    expect(playlist).to be_current
    expect(playlist.items).to be_empty
    expect(playlist.broadcast_day_starts_at).to eq(krasnoyarsk.local(2026, 9, 2).utc)
    expect(playlist.etag).to be_present
  end

  it "returns the current playlist unchanged when the fingerprint matches" do
    station = create_playlist_station!
    create(:screen, station: station)
    create_cyclic_portrait!(station, filler_rotation: create_clip_rotation!(organization: create(:organization, :client)))

    first = generate!(station)
    second = generate!(station)

    expect(second.playlist.id).to eq(first.playlist.id)
    expect(second.playlist.version).to eq(1)
    expect(Playlist.where(station: station, for_date: PlaylistGeneration::WEDNESDAY).count).to eq(1)
  end

  it "supersedes the current playlist and bumps version when inputs change" do
    station = create_playlist_station!
    create(:screen, station: station)
    portrait = create_cyclic_portrait!(station,
      filler_rotation: create_clip_rotation!(organization: create(:organization, :client)))
    first = generate!(station)
    portrait.update!(name: "Revised")

    second = generate!(station.reload)

    expect(first.playlist.reload).to be_superseded
    expect(second.playlist).to be_current
    expect(second.playlist.version).to eq(2)
    expect(second.playlist.id).not_to eq(first.playlist.id)
  end

  it "warns and skips filler when the catalog is empty" do
    station = create_playlist_station!
    create(:screen, station: station)
    empty = create(:rotation, organization: create(:organization, :client))
    create_cyclic_portrait!(station, filler_rotation: empty)

    result = generate!(station)

    expect(result.playlist).to be_current
    expect(result.playlist.items).to be_empty
    expect(result.warnings).not_to be_empty
  end

  it "warns when a welcome block has no eligible clips" do
    station = create_playlist_station!
    create(:screen, station: station)
    org = create(:organization, :client)
    empty = create(:rotation, organization: org)
    create_cyclic_portrait!(
      station,
      filler_rotation: create_clip_rotation!(organization: org),
      welcome_rotation: empty,
      close_rotation: create_clip_rotation!(organization: org)
    )

    result = generate!(station)

    expect(result.playlist).to be_current
    expect(result.warnings).to include("service welcome has no eligible clips")
  end

  it "does not wrap own_atmosphere commercials with service headers" do
    station = create_playlist_station!
    screen = create(:screen, station: station)
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    headers = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(station, filler_rotation: filler,
      header_start_rotation: headers, header_end_rotation: headers)
    occupy_with_clips!(screen: screen, organization: org,
      rotation: create_clip_rotation!(organization: org), starts_at: local_slot(9), ends_at: local_slot(21))

    playlist = generate!(station).playlist
    commercial_offsets = playlist.items.select(&:media_plan?).map(&:offset_seconds)

    expect(commercial_offsets).to be_present
    expect(source_kinds_at(playlist, commercial_offsets.min)).to eq(%w[media_plan])
  end

  it "wraps commercial placement with service header clips" do
    station = create_playlist_station!
    owner = create(:organization, :client)
    placer = create(:organization, :client)
    screen = create(:screen, station: station, owner_organization: owner)
    filler = create_clip_rotation!(organization: owner)
    start_rot = create_clip_rotation!(organization: owner)
    end_rot = create_clip_rotation!(organization: owner)
    ads = create_clip_rotation!(organization: placer)
    create_cyclic_portrait!(station, filler_rotation: filler,
      header_start_rotation: start_rot, header_end_rotation: end_rot)
    occupy_with_clips!(
      screen: screen,
      organization: placer,
      rotation: ads,
      starts_at: local_slot(9),
      ends_at: local_slot(21),
      placement_kind: :commercial,
      shows_per_hour: 2,
      group_organization: owner
    )

    playlist = generate!(station).playlist
    first_clip = playlist.items.select(&:media_plan?).min_by(&:offset_seconds)
    before = playlist.items.find { |item| item.offset_seconds < first_clip.offset_seconds && item.service? }
    after = playlist.items.find { |item| item.offset_seconds > first_clip.offset_seconds && item.service? }

    expect(before).to be_present
    expect(after).to be_present
    expect(before.media_asset_id).to eq(start_rot.ordered_items.first.media_asset_id)
    expect(after.media_asset_id).to eq(end_rot.ordered_items.first.media_asset_id)
  end

  it "places welcome and close on each screen's effective hours (AE4)" do
    station = create_playlist_station!
    screen_a = create(:screen, station: station)
    screen_b = create(
      :screen,
      station: station,
      inherit_operating_hours_from_location: false,
      operating_hours: { "wed" => [ { "start" => "10:00", "end" => "20:00" } ] }
    )
    org = create(:organization, :client)
    filler = create_clip_rotation!(organization: org)
    welcome = create_clip_rotation!(organization: org)
    close = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(station, filler_rotation: filler, welcome_rotation: welcome, close_rotation: close)

    playlist = generate!(station).playlist
    welcome_id = welcome.ordered_items.first.media_asset_id
    close_id = close.ordered_items.first.media_asset_id
    welcome_a = playlist.items.find { |item| item.service? && item.media_asset_id == welcome_id && item_screen_ids(item).include?(screen_a.id) }
    welcome_b = playlist.items.find { |item| item.service? && item.media_asset_id == welcome_id && item_screen_ids(item).include?(screen_b.id) }
    close_a = playlist.items.find { |item| item.service? && item.media_asset_id == close_id && item_screen_ids(item).include?(screen_a.id) }
    close_b = playlist.items.find { |item| item.service? && item.media_asset_id == close_id && item_screen_ids(item).include?(screen_b.id) }

    expect(welcome_a.offset_seconds).to eq(0)
    expect(item_screen_ids(welcome_a)).to eq([ screen_a.id ])
    expect(welcome_b.offset_seconds).to eq(1.hour.to_i)
    expect(item_screen_ids(welcome_b)).to eq([ screen_b.id ])
    expect(close_a.offset_seconds).to eq(12.hours.to_i)
    expect(item_screen_ids(close_a)).to eq([ screen_a.id ])
    expect(close_b.offset_seconds).to eq(11.hours.to_i)
    expect(item_screen_ids(close_b)).to eq([ screen_b.id ])
  end

  it "skips welcome and close on a closed weekday and still succeeds (AE5)" do
    station = create_playlist_station!(hours: { "mon" => [ { "start" => "09:00", "end" => "21:00" } ] })
    create(:screen, station: station)
    org = create(:organization, :client)
    create_cyclic_portrait!(
      station,
      filler_rotation: create_clip_rotation!(organization: org),
      welcome_rotation: create_clip_rotation!(organization: org),
      close_rotation: create_clip_rotation!(organization: org)
    )

    result = generate!(station)

    expect(result.skipped).to be_nil
    expect(result.playlist).to be_current
    expect(result.playlist.items.select(&:service?)).to be_empty
  end

  it "opens welcome on the first window and close on the last split-shift window (AE6)" do
    station = create_playlist_station!(
      hours: {
        "wed" => [
          { "start" => "09:00", "end" => "12:00" },
          { "start" => "14:00", "end" => "18:00" }
        ]
      }
    )
    create(:screen, station: station)
    org = create(:organization, :client)
    welcome = create_clip_rotation!(organization: org)
    close = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(
      station,
      filler_rotation: create_clip_rotation!(organization: org),
      welcome_rotation: welcome,
      close_rotation: close
    )

    playlist = generate!(station).playlist
    welcome_item = playlist.items.find { |item| item.service? && item.media_asset_id == welcome.ordered_items.first.media_asset_id }
    close_item = playlist.items.find { |item| item.service? && item.media_asset_id == close.ordered_items.first.media_asset_id }

    expect(welcome_item.offset_seconds).to eq(0)
    expect(close_item.offset_seconds).to eq(9.hours.to_i)
  end

  it "picks random service headers through NeutralPicker (AE7)" do
    station = create_playlist_station!
    owner = create(:organization, :client)
    placer = create(:organization, :client)
    screen = create(:screen, station: station, owner_organization: owner)
    start_rot = create_clip_rotation!(organization: owner, count: 3)
    end_rot = create_clip_rotation!(organization: owner)
    create_cyclic_portrait!(
      station,
      filler_rotation: create_clip_rotation!(organization: owner),
      header_start_rotation: start_rot,
      header_end_rotation: end_rot
    )
    station.screens.each do |member|
      member.broadcast_portrait.blocks.find_by!(kind: "service_header_start").update!(pick_strategy: "random")
    end
    occupy_with_clips!(
      screen: screen,
      organization: placer,
      rotation: create_clip_rotation!(organization: placer),
      starts_at: local_slot(9),
      ends_at: local_slot(21),
      placement_kind: :commercial,
      shows_per_hour: 2,
      group_organization: owner
    )
    expected = Playlists::NeutralPicker.new(
      rotation: start_rot,
      strategy: "random",
      station: station,
      for_date: PlaylistGeneration::WEDNESDAY,
      min_seconds: nil
    ).take(1).first

    playlist = generate!(station).playlist
    first_clip = playlist.items.select(&:media_plan?).min_by(&:offset_seconds)
    header = playlist.items.find { |item| item.service? && item.offset_seconds < first_clip.offset_seconds }

    expect(header.media_asset_id).to eq(expected[:media_asset].id)
  end

  it "places welcome at a screen's custom open (AE12)" do
    station = create_playlist_station!
    screen = create(
      :screen,
      station: station,
      inherit_operating_hours_from_location: false,
      operating_hours: { "wed" => [ { "start" => "08:00", "end" => "22:00" } ] }
    )
    org = create(:organization, :client)
    welcome = create_clip_rotation!(organization: org)
    create_cyclic_portrait!(
      station,
      filler_rotation: create_clip_rotation!(organization: org),
      welcome_rotation: welcome,
      close_rotation: create_clip_rotation!(organization: org)
    )

    playlist = generate!(station).playlist
    welcome_item = playlist.items.find { |item| item.service? && item.media_asset_id == welcome.ordered_items.first.media_asset_id }

    expect(playlist.broadcast_day_starts_at).to eq(local_slot(8).utc)
    expect(welcome_item.offset_seconds).to eq(0)
    expect(item_screen_ids(welcome_item)).to eq([ screen.id ])
  end
end
