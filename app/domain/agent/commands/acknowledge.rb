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
        AgentCommand.transaction do
          Array(results).each do |result|
            apply(normalize_row(result.to_h.deep_stringify_keys))
          end
        end
        nil
      end

      private

      attr_reader :station, :results

      def normalize_row(data)
        raise Invalid if data["command_id"].blank?
        raise Invalid unless data["ok"] == true || data["ok"] == false
        raise Invalid unless data["error"].nil? || data["error"].is_a?(String)

        finished_at = Time.iso8601(data["finished_at"].to_s)
        {
          "command_id" => data["command_id"],
          "ok" => data["ok"],
          "error" => data["error"],
          "finished_at" => finished_at,
          "result" => data["result"]
        }
      rescue ArgumentError
        raise Invalid
      end

      def apply(row)
        command = station.agent_commands.lock.find_by(public_id: row["command_id"])
        return if command.nil?
        return if command.acked?

        synchronize_screens(command, row)

        command.update!(
          status: "acked",
          succeeded: row["ok"],
          result_error: row["error"],
          finished_at: row["finished_at"]
        )
      end

      def synchronize_screens(command, row)
        return unless command.command_type == "fetch_screens"
        return unless row["ok"]

        result = row["result"]
        raise Invalid unless result.is_a?(Hash) && result["screens"].is_a?(Array)

        Agent::Screens::Synchronize.call(station:, screens: result["screens"])
      rescue Agent::Screens::NormalizeDiscovery::Invalid
        raise Invalid
      end
    end
  end
end
