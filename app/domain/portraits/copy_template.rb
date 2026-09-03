# frozen_string_literal: true

module Portraits
  class CopyTemplate < BaseService
    def initialize(station:, template: nil, replace: false)
      @station = station
      @template = template
      @replace = replace
    end

    def call
      BroadcastPortrait.transaction do
        existing = station.broadcast_portrait
        if existing
          return existing unless replace

          existing.destroy!
          station.reload_broadcast_portrait
        end

        source = template || BroadcastPortrait.templates.find_by(is_default: true)
        return if source.nil?

        copy_from(source)
      end
    end

    private

    attr_reader :station, :template, :replace

    def copy_from(source)
      portrait = station.create_broadcast_portrait!(
        name: source.name,
        kind: source.kind,
        block_frequency_per_hour: source.block_frequency_per_hour,
        max_commercial_in_row: source.max_commercial_in_row,
        neutral_min_seconds: source.neutral_min_seconds,
        is_default: false
      )
      source.blocks.order(:position).each do |block|
        portrait.blocks.create!(
          position: block.position,
          kind: block.kind,
          rotation_id: block.rotation_id,
          pick_strategy: block.pick_strategy,
          time_of_day: block.time_of_day
        )
      end
      Playlists::EnqueueRegen.from_station(station) if replace
      portrait
    end
  end
end
