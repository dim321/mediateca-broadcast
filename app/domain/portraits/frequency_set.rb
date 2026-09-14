# frozen_string_literal: true

module Portraits
  class FrequencySet
    def self.intersection_for_screens(screens)
      list = Array(screens)
      return [] if list.empty?

      list.map { |screen| Array(screen.broadcast_portrait&.block_frequencies_per_hour) }
        .reduce { |acc, set| acc & set }
        .sort
    end
  end
end
