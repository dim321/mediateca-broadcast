# frozen_string_literal: true

module ServiceThemes
  class RemoveClip < BaseService
    def initialize(theme:, rotation_item:)
      @theme = theme
      @rotation_item = rotation_item
    end

    def call
      rotation = rotation_item.rotation
      raise ArgumentError, "clip is not in this theme" unless theme_folder?(rotation)

      rotation_item.destroy!
      Playlists::EnqueueRegen.from_rotation(rotation)
      rotation_item
    end

    private

    attr_reader :theme, :rotation_item

    def theme_folder?(rotation)
      theme.rotations.any? { |folder| folder.id == rotation.id }
    end
  end
end
