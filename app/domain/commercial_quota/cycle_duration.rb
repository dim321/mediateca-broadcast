# frozen_string_literal: true

module CommercialQuota
  class CycleDuration < ServiceObject
    DEFAULT_ITEM_SECONDS = 15

    def initialize(rotation:)
      @rotation = rotation
    end

    def call
      items = rotation.ordered_items
      return DEFAULT_ITEM_SECONDS if items.empty?

      items.sum { |item| item_seconds(item) }
    end

    private

    attr_reader :rotation

    def item_seconds(item)
      item.display_duration_seconds.presence ||
        item.media_asset&.duration_seconds.presence ||
        DEFAULT_ITEM_SECONDS
    end
  end
end
