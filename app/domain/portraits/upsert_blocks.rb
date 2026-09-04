# frozen_string_literal: true

module Portraits
  class UpsertBlocks < BaseService
    def initialize(portrait:, blocks:)
      @portrait = portrait
      @blocks = Array(blocks)
    end

    def call
      result = BroadcastPortraitBlock.transaction do
        portrait.blocks.delete_all
        blocks.each do |attrs|
          portrait.blocks.create!(block_attributes(attrs))
        end
        portrait.update!(service_theme: nil) if portrait.service_theme_id.present?
        portrait.blocks.reload
      end
      Playlists::EnqueueRegen.from_screen(portrait.screen) if portrait.screen
      result
    end

    private

    attr_reader :portrait, :blocks

    def block_attributes(attrs)
      attrs = attrs.to_h.with_indifferent_access
      attrs.slice(:position, :kind, :rotation_id, :pick_strategy, :time_of_day)
    end
  end
end
