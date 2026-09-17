# frozen_string_literal: true

module CommercialQuota
  class HourlyShowsDuration < ServiceObject
    def initialize(rotation:, shows_per_hour:)
      @rotation = rotation
      @shows_per_hour = shows_per_hour.to_i
    end

    def call
      return 0 if shows_per_hour < 1

      catalog = rotation.ordered_items
      return shows_per_hour * CycleDuration::DEFAULT_ITEM_SECONDS if catalog.empty?

      durations = catalog.map { |item| item_seconds(item) }
      shows_per_hour.times.sum { |i| durations[i % durations.size] }
    end

    private

    attr_reader :rotation, :shows_per_hour

    def item_seconds(item)
      item.display_duration_seconds.presence ||
        item.media_asset&.duration_seconds.presence ||
        CycleDuration::DEFAULT_ITEM_SECONDS
    end
  end
end
