# frozen_string_literal: true

module Rotations
  class RotationItemComponent < ViewComponent::Base
    def initialize(rotation:, item:)
      @rotation = rotation
      @item = item
    end

    attr_reader :rotation, :item

    def duration_label
      seconds = item.display_duration_seconds.presence || item.media_asset.duration_seconds
      return "—" if seconds.blank?

      "#{seconds}s"
    end
  end
end
