# frozen_string_literal: true

module Playlists
  class NeutralGapFill
    def self.call(clips:, window_seconds:)
      new(clips: clips, window_seconds: window_seconds).call
    end

    def initialize(clips:, window_seconds:)
      @clips = Array(clips)
      @window_seconds = window_seconds.to_i
    end

    def call
      return [] if window_seconds <= 0 || ranked.empty?

      remaining = window_seconds
      index = 0
      placed = []
      while remaining.positive?
        choice = next_fit(index, remaining)
        break unless choice

        placed << choice.fetch(:clip)
        remaining -= choice.fetch(:clip).fetch(:duration_seconds)
        index = choice.fetch(:next_index)
      end
      placed
    end

    private

    attr_reader :clips, :window_seconds

    def ranked
      @ranked ||= clips.sort_by { |clip| [ -clip.fetch(:duration_seconds).to_i, clip[:position].to_i ] }
    end

    def next_fit(start_index, remaining)
      ranked.size.times do |offset|
        idx = (start_index + offset) % ranked.size
        clip = ranked[idx]
        duration = clip.fetch(:duration_seconds).to_i
        next if duration <= 0 || duration > remaining

        return { clip: clip, next_index: (idx + 1) % ranked.size }
      end
      nil
    end
  end
end
