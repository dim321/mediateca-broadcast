# frozen_string_literal: true

module Agent
  module Commands
    class Queue < BaseService
      def self.etag(station:)
        body = pending(station).map { |command| "#{command.public_id}@#{command.issued_at.utc.iso8601}" }.join("\n")
        %("#{Digest::SHA256.hexdigest(body)}")
      end

      def self.pending(station)
        station.agent_commands.pending.order(:issued_at, :id)
      end

      def initialize(station:)
        @station = station
      end

      def call
        self.class.pending(station).map { |command| payload(command) }
      end

      private

      attr_reader :station

      def payload(command)
        {
          id: command.public_id,
          screen_id: command.screen_id,
          type: command.command_type,
          params: command.params,
          issued_at: command.issued_at.utc.iso8601
        }
      end
    end
  end
end
