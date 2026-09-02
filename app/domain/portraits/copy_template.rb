# frozen_string_literal: true

module Portraits
  class CopyTemplate < BaseService
    def initialize(station:)
      @station = station
    end

    def call
      return station.broadcast_portrait if station.broadcast_portrait.present?

      template = BroadcastPortrait.find_by(station_id: nil, is_default: true)
      return if template.nil?

      BroadcastPortrait.transaction do
        portrait = station.create_broadcast_portrait!(
          name: template.name,
          kind: template.kind,
          block_frequency_per_hour: template.block_frequency_per_hour,
          max_commercial_in_row: template.max_commercial_in_row,
          neutral_min_seconds: template.neutral_min_seconds,
          is_default: false
        )
        template.blocks.order(:position).each do |block|
          portrait.blocks.create!(
            position: block.position,
            kind: block.kind,
            rotation_id: block.rotation_id,
            pick_strategy: block.pick_strategy,
            time_of_day: block.time_of_day
          )
        end
        portrait
      end
    end

    private

    attr_reader :station
  end
end
