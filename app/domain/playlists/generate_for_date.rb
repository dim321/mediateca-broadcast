# frozen_string_literal: true

module Playlists
  class GenerateForDate < BaseService
    Result = Data.define(:playlist, :warnings, :skipped)

    def initialize(station:, for_date:)
      @station = station
      @for_date = for_date.to_date
      @warnings = []
    end

    def call
      ApplicationRecord.transaction do
        StationDateLock.call(station: station)
        screens = load_screens
        ensure_portraits!(screens)
        return Result.new(playlist: nil, warnings: [], skipped: :missing_portrait) if screens.none? { |screen| screen.broadcast_portrait }

        fingerprint = Fingerprint.call(station: station, for_date: for_date)
        current = Playlist.current.find_by(station: station, for_date: for_date)
        if current&.fingerprint == fingerprint
          return Result.new(playlist: current, warnings: [], skipped: nil)
        end

        entries = build_entries(screens)
        playlist = persist(current, fingerprint, entries)
        Result.new(playlist: playlist, warnings: warnings.uniq, skipped: nil)
      end
    end

    private

    attr_reader :station, :for_date, :warnings, :anchor

    def load_screens
      station.screens.order(:id).includes(:broadcast_portrait).to_a
    end

    def ensure_portraits!(screens)
      screens.each do |screen|
        next if screen.broadcast_portrait

        Portraits::CopyTemplate.call(screen: screen)
        screen.reload_broadcast_portrait
      end
    end

    def build_entries(screens)
      window_starts = screens.flat_map { |screen| operating_windows(screen).map { |window| window[:start] } }
      if window_starts.empty?
        @anchor = zone.local(for_date.year, for_date.month, for_date.day)
        return []
      end

      @anchor = window_starts.min
      emissions = screens.flat_map { |screen| emissions_for_screen(screen) }
      merge_emissions(emissions)
    end

    def persist(current, fingerprint, entries)
      positioned = entries.each_with_index.map { |entry, index| entry.merge(position: index + 1) }
      current&.update_columns(status: Playlist.statuses.fetch("superseded"))
      playlist = station.playlists.create!(
        for_date: for_date,
        version: current ? current.version + 1 : 1,
        status: "current",
        generated_at: Time.current,
        broadcast_day_starts_at: anchor,
        fingerprint: fingerprint,
        etag: Digest::SHA256.hexdigest(JSON.generate(etag_payload(positioned)))
      )
      positioned.each { |entry| create_item!(playlist, entry) }
      playlist.items.includes(:screens, :media_asset).load
      playlist
    end

    def create_item!(playlist, entry)
      item = playlist.items.build(
        position: entry[:position],
        media_asset_id: entry[:media_asset_id],
        offset_seconds: entry[:offset_seconds],
        duration_seconds: entry[:duration_seconds],
        source_kind: entry[:source_kind],
        media_plan_id: entry[:media_plan_id]
      )
      entry[:screen_ids].each { |screen_id| item.playlist_item_screens.build(screen_id: screen_id) }
      item.save!
    end

    def etag_payload(entries)
      entries.map do |entry|
        {
          position: entry[:position],
          media_asset_id: entry[:media_asset_id],
          offset_seconds: entry[:offset_seconds],
          duration_seconds: entry[:duration_seconds],
          source_kind: entry[:source_kind],
          media_plan_id: entry[:media_plan_id],
          screen_ids: entry[:screen_ids].sort
        }
      end
    end

    def emissions_for_screen(screen)
      portrait = screen.broadcast_portrait
      return [] unless portrait

      windows = operating_windows(screen)
      return [] if windows.empty?

      pickers = {}
      cycle_index = 0
      cycle = cycle_blocks(portrait)
      insertions = insertion_events(portrait)
      slots = build_slots(windows, screen, portrait)
      day_bound_emissions(screen, portrait, windows, pickers) + slots.flat_map do |slot_start, slot_end, index, count, covering|
        matching = insertions.select { |event| slot_start <= event[:at] && event[:at] < slot_end }.map { |event| event[:block] }
        if matching.any?
          cycle_index += 1 if cycle.any?
          matching.flat_map { |block| emit_insertion(block, screen, portrait, slot_start, pickers) }
        elsif Playlists::HourGrid.catalog_frequencies(covering).any?
          emit_beat_slot(screen, portrait, slot_start, index, count, covering, pickers)
        elsif cycle.empty?
          []
        else
          block = cycle[cycle_index % cycle.size]
          cycle_index += 1
          emit_cycle_block(block, screen, portrait, slot_start, pickers)
        end
      end
    end

    def emit_insertion(block, screen, portrait, slot_start, pickers)
      pick = take_from_block(block, screen, pickers, min_seconds: portrait.neutral_min_seconds)
      return [ emission(pick, screen, slot_start, "insertion") ] if pick

      warn_once("insertion rotation #{block.rotation_id} has no eligible clips")
      []
    end

    def emit_cycle_block(block, screen, portrait, slot_start, pickers)
      case block.kind
      when "commercial"
        emit_commercial(screen, portrait, slot_start, pickers)
      when "filler"
        emit_filler(block, screen, portrait, slot_start, pickers)
      when "service_header_start", "service_header_end"
        emit_service_cycle(block, screen, slot_start, pickers)
      else
        []
      end
    end

    def emit_commercial(screen, portrait, slot_start, pickers)
      plans = occupying_plans_for(screen, slot_start)
      return emit_commercial_fallback(screen, portrait, slot_start, pickers) if plans.empty?

      if plans.one? && plans.first.advertising_order_line_id.nil?
        return emit_single_plan_commercial(plans.first, screen, portrait, slot_start, pickers)
      end

      emit_mixed_commercial(plans, screen, portrait, slot_start, pickers)
    end

    def emit_single_plan_commercial(plan, screen, portrait, slot_start, pickers)
      clips = commercial_clips(plan, screen, pickers)
      return [] if clips.empty?

      wrap_commercial_emissions(plan.commercial?, screen, portrait, slot_start, pickers) do |offset|
        clips.map do |clip|
          item = emission(clip, screen, offset, "media_plan", media_plan_id: plan.id)
          offset += clip[:duration_seconds]
          item
        end
      end
    end

    def emit_beat_slot(screen, portrait, slot_start, index, slot_count, covering, pickers)
      hitters = covering.select { |plan| Playlists::HourGrid.catalog_hit?(plan, index, slot_count) }
      extras = covering.select do |plan|
        plan.commercial? && plan.shows_per_hour.present? && !Playlists::HourGrid.catalog_frequency?(plan.shows_per_hour)
      end
      players = hitters + extras
      return emit_commercial_fallback(screen, portrait, slot_start, pickers) if players.empty?

      emit_mixed_commercial(players, screen, portrait, slot_start, pickers, clips_per_plan: 1)
    end

    def emit_mixed_commercial(plans, screen, portrait, slot_start, pickers, clips_per_plan: nil)
      remaining = portrait.max_commercial_in_row
      batches = []
      plans.each do |plan|
        break if remaining <= 0

        per_plan = clips_per_plan || commercial_clip_count(plan, portrait)
        count = [ per_plan, remaining ].min
        next if count < 1

        clips = commercial_clips(plan, screen, pickers, count: count)
        next if clips.empty?

        remaining -= clips.size
        batches << [ plan, clips ]
      end
      return [] if batches.empty?

      wrap_commercial_emissions(plans.any?(&:commercial?), screen, portrait, slot_start, pickers) do |offset|
        round_robin_plan_clips(batches).map do |plan, clip|
          item = emission(clip, screen, offset, "media_plan", media_plan_id: plan.id)
          offset += clip[:duration_seconds]
          item
        end
      end
    end

    def wrap_commercial_emissions(wrap, screen, portrait, slot_start, pickers)
      offset = offset_seconds(slot_start)
      items = []
      if wrap
        header_blocks(portrait, "service_header_start").each do |block|
          pick = take_from_block(block, screen, pickers, min_seconds: nil)
          if pick
            items << emission(pick, screen, offset, "service")
            offset += pick[:duration_seconds]
          else
            warn_once("service header start has no eligible clips")
          end
        end
      end
      items.concat(yield(offset))
      if items.any?
        last = items.last
        offset = last[:offset_seconds] + last[:duration_seconds]
      end
      if wrap
        header_blocks(portrait, "service_header_end").each do |block|
          pick = take_from_block(block, screen, pickers, min_seconds: nil)
          if pick
            items << emission(pick, screen, offset, "service")
            offset += pick[:duration_seconds]
          else
            warn_once("service header end has no eligible clips")
          end
        end
      end
      items
    end

    def round_robin_plan_clips(batches)
      queues = batches.map { |plan, clips| clips.map { |clip| [ plan, clip ] } }
      interleaved = []
      loop do
        progressed = false
        queues.each do |queue|
          pair = queue.shift
          next unless pair

          interleaved << pair
          progressed = true
        end
        break unless progressed
      end
      interleaved
    end

    def emit_commercial_fallback(screen, portrait, slot_start, pickers)
      filler = cycle_blocks(portrait).find(&:filler?)
      unless filler
        warn_once("no occupying plan and no filler block")
        return []
      end

      emit_filler(filler, screen, portrait, slot_start, pickers)
    end

    def emit_filler(block, screen, portrait, slot_start, pickers)
      pick = take_from_block(block, screen, pickers, min_seconds: portrait.neutral_min_seconds)
      return [ emission(pick, screen, slot_start, "filler") ] if pick

      warn_once("filler rotation #{block.rotation_id} has no eligible clips")
      []
    end

    def emit_service_cycle(block, screen, slot_start, pickers)
      pick = take_from_block(block, screen, pickers, min_seconds: nil)
      return [ emission(pick, screen, slot_start, "service") ] if pick

      warn_once("service header block has no eligible clips")
      []
    end

    def commercial_clips(plan, screen, pickers, count: nil)
      picker = picker_for(pickers, screen, plan.rotation, "sequential", min_seconds: nil)
      clips = picker.take(count || commercial_clip_count(plan, screen.broadcast_portrait))
      if clips.empty?
        warn_once("media plan #{plan.id} rotation has no eligible clips")
        return []
      end

      clips
    end

    def commercial_clip_count(plan, portrait)
      return 1 if plan.shows_per_hour.nil?

      n = portrait.hour_slot_count
      [ (plan.shows_per_hour.to_f / n).ceil.to_i, portrait.max_commercial_in_row ].min
    end

    def take_from_block(block, screen, pickers, min_seconds:)
      return if block.rotation.nil?

      strategy = block.pick_strategy.presence || "sequential"
      picker_for(pickers, screen, block.rotation, strategy, min_seconds: min_seconds).take(1).first
    end

    def picker_for(pickers, screen, rotation, strategy, min_seconds:)
      key = [ screen.id, rotation.id, strategy, min_seconds ]
      pickers[key] ||= NeutralPicker.new(
        rotation: rotation,
        strategy: strategy,
        station: station,
        for_date: for_date,
        min_seconds: min_seconds
      )
    end

    def emission(pick, screen, time_or_offset, source_kind, media_plan_id: nil)
      offset = time_or_offset.is_a?(Integer) ? time_or_offset : offset_seconds(time_or_offset)
      {
        media_asset_id: pick[:media_asset].id,
        duration_seconds: pick[:duration_seconds],
        offset_seconds: offset,
        source_kind: source_kind,
        media_plan_id: media_plan_id,
        screen_ids: [ screen.id ]
      }
    end

    def merge_emissions(emissions)
      emissions
        .group_by { |entry| [ entry[:offset_seconds], entry[:media_asset_id], entry[:source_kind], entry[:media_plan_id] ] }
        .map do |_key, rows|
          rows.first.merge(screen_ids: rows.flat_map { |row| row[:screen_ids] }.uniq.sort)
        end
        .sort_by { |entry| [ entry[:offset_seconds], entry[:source_kind].to_s, entry[:media_asset_id] ] }
    end

    def occupying_plans_for(screen, slot_start)
      occupying_plans.select do |plan|
        next false unless plan_covers_screen?(plan, screen)

        plan.starts_at <= slot_start && slot_start < plan.ends_at
      end
    end

    def plan_covers_screen?(plan, screen)
      plan.media_plan_screens.any? { |row| row.screen_id == screen.id } ||
        Array(plan.broadcast_point_group&.screens).any? { |member| member.id == screen.id }
    end

    def occupying_plans
      @occupying_plans ||= Fingerprint.occupying_plans(station: station, for_date: for_date)
    end

    def insertion_events(portrait)
      portrait.blocks.select(&:insertion?).filter_map do |block|
        tod = block.time_of_day
        next unless tod

        at = local_wall_clock(tod.hour, tod.min)
        next unless at

        { block: block, at: at }
      end
    end

    def cycle_blocks(portrait)
      portrait.blocks.sort_by(&:position).reject do |block|
        block.insertion? || block.service_welcome? || block.service_close?
      end
    end

    def day_bound_emissions(screen, portrait, windows, pickers)
      open_at = windows.first[:start]
      close_at = windows.last[:end]
      emissions = []
      header_blocks(portrait, "service_welcome").each do |block|
        pick = take_from_block(block, screen, pickers, min_seconds: nil)
        if pick
          emissions << emission(pick, screen, open_at, "service")
        else
          warn_once("service welcome has no eligible clips")
        end
      end
      header_blocks(portrait, "service_close").each do |block|
        pick = take_from_block(block, screen, pickers, min_seconds: nil)
        if pick
          emissions << emission(pick, screen, close_at, "service")
        else
          warn_once("service close has no eligible clips")
        end
      end
      emissions
    end

    def header_blocks(portrait, kind)
      portrait.blocks.sort_by(&:position).select { |block| block.kind == kind }
    end

    def operating_windows(screen)
      Location::OperatingHours.day_windows(screen.effective_operating_hours, for_date).filter_map do |window|
        win_start = parse_hhmm(window[:start])
        win_end = parse_hhmm(window[:end])
        next if win_start.nil? || win_end.nil? || win_end <= win_start

        { start: win_start, end: win_end }
      end.sort_by { |window| window[:start] }
    end

    def build_slots(windows, screen, portrait)
      windows.flat_map do |window|
        hour = window[:start].change(min: 0, sec: 0)
        slots = []
        while hour < window[:end]
          hour_end = hour + 3600
          covering = occupying_plans.select do |plan|
            plan_covers_screen?(plan, screen) && plan.starts_at < hour_end && plan.ends_at > hour
          end
          count = Playlists::HourGrid.slot_count(portrait: portrait, occupying_plans: covering)
          step = 3600 / count
          count.times do |index|
            slot_start = hour + (step * index)
            slot_end = slot_start + step
            next if slot_end <= window[:start] || slot_start >= window[:end]

            clipped_start = slot_start < window[:start] ? window[:start] : slot_start
            clipped_end = slot_end > window[:end] ? window[:end] : slot_end
            slots << [ clipped_start, clipped_end, index, count, covering ]
          end
          hour = hour_end
        end
        slots
      end
    end

    def parse_hhmm(value)
      hour, min = value.to_s.split(":").map(&:to_i)
      local_wall_clock(hour, min)
    end

    def local_wall_clock(hour, min)
      dummy = Time.new(for_date.year, for_date.month, for_date.day, hour, min, 0)
      utc = zone.tzinfo.local_to_utc(dummy) { |periods| periods.min_by { |period| period.starts_at || Time.at(0) } }
      zone.at(utc)
    rescue TZInfo::PeriodNotFound
      nil
    end

    def offset_seconds(time)
      (time - anchor).to_i
    end

    def zone
      @zone ||= Time.find_zone!(station.location.time_zone)
    end

    def warn_once(message)
      warnings << message unless warnings.include?(message)
    end
  end
end
