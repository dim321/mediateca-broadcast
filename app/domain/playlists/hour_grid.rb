# frozen_string_literal: true

module Playlists
  class HourGrid
    CATALOG = BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR

    def self.slot_count(portrait:, occupying_plans:)
      freqs = catalog_frequencies(occupying_plans)
      return Integer(portrait.hour_slot_count) if freqs.empty?

      freqs.reduce(:lcm)
    end

    def self.catalog_hit?(plan, index, slot_count)
      freq = plan.shows_per_hour
      return false unless catalog_frequency?(freq)
      return false if slot_count.to_i <= 0 || (slot_count % freq).nonzero?

      (index % (slot_count / freq)).zero?
    end

    def self.catalog_frequency?(value)
      value.present? && CATALOG.include?(value)
    end

    def self.catalog_frequencies(plans)
      Array(plans).filter_map do |plan|
        next unless plan.commercial?

        freq = plan.shows_per_hour
        freq if catalog_frequency?(freq)
      end.uniq
    end
  end
end
