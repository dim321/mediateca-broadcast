# frozen_string_literal: true

module Agent
  module Commands
    class FetchScreens < BaseService
      Result = Data.define(:command, :created) do
        def created? = created
      end

      def initialize(station:)
        @station = station
      end

      def call
        command = pending
        return Result.new(command:, created: false) if command

        Result.new(command: create_command, created: true)
      rescue ActiveRecord::RecordNotUnique
        Result.new(command: pending!, created: false)
      end

      private

      attr_reader :station

      def pending
        station.agent_commands.pending.find_by(command_type: "fetch_screens")
      end

      def pending!
        station.agent_commands.pending.find_by!(command_type: "fetch_screens")
      end

      def create_command
        AgentCommand.transaction(requires_new: true) do
          station.agent_commands.create!(
            screen: nil,
            public_id: "cmd_#{SecureRandom.uuid}",
            command_type: "fetch_screens",
            params: {},
            issued_at: Time.current,
            status: "pending"
          )
        end
      end
    end
  end
end
