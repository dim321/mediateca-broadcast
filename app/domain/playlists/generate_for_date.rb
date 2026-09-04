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
      slots = build_slots(windows, portrait)
      slots.flat_map do |slot_start, slot_end|
        matching = insertions.select { |event| slot_start <= event[:at] && event[:at] < slot_end }.map { |event| event[:block] }
        if matching.any?
          cycle_index += 1 if cycle.any?
          matching.flat_map { |block| emit_insertion(block, screen, portrait, slot_start, pickers) }
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
        emit_service_cycle(block, screen, slot_start)
      else
        []
      end
    end

    def emit_commercial(screen, portrait, slot_start, pickers)
      plan = occupying_plan_for(screen, slot_start)
      return emit_commercial_fallback(screen, portrait, slot_start, pickers) unless plan

      clips = commercial_clips(plan, screen, pickers)
      return [] if clips.empty?

      offset = offset_seconds(slot_start)
      items = []
      if plan.commercial?
        header_blocks(portrait, "service_header_start").each do |block|
          pick = header_pick(block)
          if pick
            items << emission(pick, screen, offset, "service")
            offset += pick[:duration_seconds]
          else
            warn_once("service header start has no eligible clips")
          end
        end
      end
      clips.each do |clip|
        items << emission(clip, screen, offset, "media_plan", media_plan_id: plan.id)
        offset += clip[:duration_seconds]
      end
      if plan.commercial?
        header_blocks(portrait, "service_header_end").each do |block|
          pick = header_pick(block)
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

    def emit_service_cycle(block, screen, slot_start)
      pick = header_pick(block)
      return [ emission(pick, screen, slot_start, "service") ] if pick

      warn_once("service header block has no eligible clips")
      []
    end

    def commercial_clips(plan, screen, pickers)
      picker = picker_for(pickers, screen, plan.rotation, "sequential", min_seconds: nil)
      clips = picker.take(commercial_clip_count(plan, screen.broadcast_portrait))
      if clips.empty?
        warn_once("media plan #{plan.id} rotation has no eligible clips")
        return []
      end

      clips
    end

    def commercial_clip_count(plan, portrait)
      return 1 if plan.shows_per_hour.nil?

      n = portrait.block_frequency_per_hour
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

    def header_pick(block)
      return if block.rotation.nil?

      block.rotation.ordered_items.each do |item|
        next unless item.media_asset.broadcast_delivery_attachment

        duration = item.display_duration_seconds.presence || item.media_asset.duration_seconds
        next if duration.blank? || duration.to_i <= 0

        return { media_asset: item.media_asset, duration_seconds: duration.to_i }
      end
      nil
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

    def occupying_plan_for(screen, slot_start)
      occupying_plans.find do |plan|
        next unless plan.broadcast_point_group.screens.any? { |member| member.id == screen.id }

        plan.starts_at <= slot_start && slot_start < plan.ends_at
      end
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
      portrait.blocks.sort_by(&:position).reject(&:insertion?)
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

    def build_slots(windows, portrait)
      step = 3600 / portrait.block_frequency_per_hour
      windows.flat_map do |window|
        slots = []
        t = window[:start]
        while t < window[:end]
          slot_end = t + step
          slot_end = window[:end] if slot_end > window[:end]
          slots << [ t, slot_end ]
          t = slot_end
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
