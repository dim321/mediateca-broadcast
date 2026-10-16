# frozen_string_literal: true

module Agent
  module StreamChannels
    class Reconcile < BaseService
      def initialize(station:, digests_by_screen_id:, horizon_complete:)
        @station = station
        @digests_by_screen_id = digests_by_screen_id
        @horizon_complete = horizon_complete
      end

      def call
        station.with_lock do
          sync_registry! if horizon_complete
          ports_by_screen_id
        end
      end

      private

      attr_reader :station, :digests_by_screen_id, :horizon_complete

      def sync_registry!
        keep = digests_by_screen_id.values.uniq
        if keep.empty?
          station.stream_channels.delete_all
        else
          station.stream_channels.where.not(timeline_digest: keep).delete_all
        end
        assign_missing!(keep.sort)
      end

      def assign_missing!(keep)
        present = station.stream_channels.pluck(:timeline_digest)
        taken = station.stream_channels.pluck(:stream_port)
        (keep - present).each do |timeline_digest|
          port = (StationStreamChannel::PORT_POOL.to_a - taken).min
          break unless port

          station.stream_channels.create!(timeline_digest:, stream_port: port)
          taken << port
        end
      end

      def ports_by_screen_id
        by_digest = station.stream_channels.pluck(:timeline_digest, :stream_port).to_h
        digests_by_screen_id.each_with_object({}) do |(screen_id, timeline_digest), ports|
          port = by_digest[timeline_digest]
          ports[screen_id] = port if port
        end
      end
    end
  end
end
