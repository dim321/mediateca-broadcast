# frozen_string_literal: true

module Agent
  module Commands
    class Acknowledge < BaseService
      class Invalid < StandardError
        attr_reader :code

        def initialize(code = "invalid_result")
          @code = code
          super(code)
        end
      end

      def initialize(station:, results:)
        @station = station
        @results = results
      end

      def call
        rows = normalize
        AgentCommand.transaction do
          rows.each { |row| apply(row) }
        end
        nil
      end

      private

      attr_reader :station, :results

      def normalize
        Array(results).map { |result| normalize_row(result.to_h.deep_stringify_keys) }
      end

      def normalize_row(data)
        raise Invalid if data["command_id"].blank?
        raise Invalid unless data["ok"] == true || data["ok"] == false
        raise Invalid unless data["error"].nil? || data["error"].is_a?(String)

        finished_at = Time.iso8601(data["finished_at"].to_s)
        {
          "command_id" => data["command_id"],
          "ok" => data["ok"],
          "error" => data["error"],
          "finished_at" => finished_at
        }
      rescue ArgumentError
        raise Invalid
      end

      def apply(row)
        command = station.agent_commands.find_by(public_id: row["command_id"])
        return if command.nil?
        return if command.acked?

        command.update!(
          status: "acked",
          succeeded: row["ok"],
          result_error: row["error"],
          finished_at: row["finished_at"]
        )
      end
    end
  end
end
