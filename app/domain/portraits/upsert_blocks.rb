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
      sliced = attrs.slice(:position, :kind, :rotation_id, :pick_strategy, :time_of_day, :service_theme_id)
      bind_service_theme(sliced)
    end

    def bind_service_theme(attrs)
      kind = attrs[:kind].to_s
      if ServiceTheme::ROTATION_ROLES.value?(kind)
        attrs[:rotation_id] = nil if attrs[:service_theme_id].blank?
      else
        attrs[:service_theme_id] = nil
      end
      attrs
    end
  end
end
