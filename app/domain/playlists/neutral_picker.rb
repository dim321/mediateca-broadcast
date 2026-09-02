# frozen_string_literal: true

module Playlists
  class NeutralPicker
    def initialize(rotation:, strategy:, station:, for_date:, min_seconds: nil)
      @rotation = rotation
      @strategy = strategy.to_s
      @station = station
      @for_date = for_date.to_date
      @min_seconds = min_seconds
      @cursor = 0
      @sequence = build_sequence
    end

    def take(count)
      return [] if sequence.empty? || count.to_i <= 0

      Array.new(count) { next_pick }
    end

    private

    attr_reader :rotation, :strategy, :station, :for_date, :min_seconds, :sequence

    def next_pick
      item = sequence[@cursor % sequence.size]
      @cursor += 1
      { media_asset: item.media_asset, duration_seconds: duration_for(item) }
    end

    def build_sequence
      catalog = rotation.ordered_items.select { |item| eligible?(item) }
      return [] if catalog.empty?

      case strategy
      when "ordered" then catalog
      when "random" then catalog.shuffle(random: rng)
      else
        offset = (for_date - Date.new(1970, 1, 1)).to_i
        catalog.rotate(offset % catalog.size)
      end
    end

    def eligible?(item)
      return false unless item.media_asset.broadcast_delivery_attachment

      duration = duration_for(item)
      return false if duration.blank? || duration <= 0
      return false if min_seconds.present? && duration < min_seconds

      true
    end

    def duration_for(item)
      raw = item.display_duration_seconds.presence || item.media_asset.duration_seconds
      raw&.to_i
    end

    def rng
      digest = Digest::SHA256.digest("v1|#{station.id}|#{for_date.iso8601}|#{rotation.id}")
      Random.new(digest[0, 8].unpack1("Q>"))
    end
  end
end
