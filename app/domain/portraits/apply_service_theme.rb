# frozen_string_literal: true

module Portraits
  class ApplyServiceTheme < BaseService
    DEFAULT_STRATEGY = "sequential"

    def initialize(portrait:, theme:, pick_strategies: {})
      @portrait = portrait
      @theme = theme
      @pick_strategies = pick_strategies.to_h.with_indifferent_access
    end

    def call
      BroadcastPortrait.transaction do
        if theme.nil?
          clear_theme!
        else
          apply_theme!
        end
      end
      Playlists::EnqueueRegen.from_screen(portrait.screen) if portrait.screen
      portrait
    end

    private

    attr_reader :portrait, :theme, :pick_strategies

    def apply_theme!
      next_position = portrait.blocks.maximum(:position).to_i
      ServiceTheme::ROTATION_ROLES.each do |role, kind|
        block = portrait.blocks.find_or_initialize_by(kind: kind)
        if block.new_record?
          next_position += 1
          block.position = next_position
        end
        block.assign_attributes(
          rotation: theme.rotation_for(role),
          pick_strategy: strategy_for(role),
          time_of_day: nil
        )
        block.save!
      end
      portrait.update!(service_theme: theme)
    end

    def clear_theme!
      portrait.blocks.where(kind: ServiceTheme::ROTATION_ROLES.values).find_each(&:destroy!)
      portrait.update!(service_theme: nil)
    end

    def strategy_for(role)
      raw = pick_strategies[role].presence ||
        pick_strategies[ServiceTheme::ROTATION_ROLES.fetch(role)].presence ||
        DEFAULT_STRATEGY
      return raw if BroadcastPortraitBlock.pick_strategies.key?(raw)

      DEFAULT_STRATEGY
    end
  end
end
