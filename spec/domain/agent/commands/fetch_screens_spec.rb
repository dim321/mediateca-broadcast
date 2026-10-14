# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Commands::FetchScreens do
  let(:station) { create(:station) }

  it "creates a pending station command with the expected attributes" do
    result = described_class.call(station:)

    expect(result).to be_created
    expect(result.command).to have_attributes(
      station: station,
      screen: nil,
      command_type: "fetch_screens",
      params: {},
      status: "pending"
    )
    expect(result.command.public_id).to start_with("cmd_")
    expect(result.command.issued_at).to be_present
  end

  it "reuses the pending command" do
    first = described_class.call(station:)
    second = described_class.call(station:)

    expect(second).not_to be_created
    expect(second.command).to eq(first.command)
    expect(station.agent_commands.where(command_type: "fetch_screens").count).to eq(1)
  end

  it "creates a new pending command after the previous command is acknowledged" do
    first = described_class.call(station:)
    first.command.update!(status: "acked")

    second = described_class.call(station:)

    expect(second).to be_created
    expect(second.command).not_to eq(first.command)
    expect(station.agent_commands.pending.where(command_type: "fetch_screens").count).to eq(1)
  end

  it "queues commands independently for different stations" do
    other_station = create(:station)

    first = described_class.call(station:)
    second = described_class.call(station: other_station)

    expect(first).to be_created
    expect(second).to be_created
    expect(first.command.station).to eq(station)
    expect(second.command.station).to eq(other_station)
  end

  it "recovers from a unique violation without aborting an outer transaction" do
    winner = nil
    racing_service = Class.new(described_class) do
      def initialize(station:, before_create:)
        super(station:)
        @before_create = before_create
      end

      private

      def pending
        command = super
        return command unless @before_create

        @before_create.call
        @before_create = nil
        nil
      end
    end

    AgentCommand.transaction do
      result = racing_service.call(
        station:,
        before_create: -> { winner = create(:agent_command, :fetch_screens, station:) }
      )

      expect(result).not_to be_created
      expect(result.command).to eq(winner)
      expect(result.command.update!(status: "acked")).to be(true)
    end
  end

  it "returns one command from two concurrent calls", :concurrency do
    committed_station = create(:station)
    ready = Queue.new
    go = Queue.new
    outcomes = Queue.new
    racing_service = Class.new(described_class) do
      def initialize(station:, ready:, go:)
        super(station:)
        @ready = ready
        @go = go
      end

      private

      def pending
        command = super
        return command if command

        @ready << true
        @go.pop
        nil
      end
    end

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          outcomes << racing_service.call(station: committed_station, ready:, go:)
        rescue StandardError => error
          outcomes << error
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    results = Array.new(2) { outcomes.pop }
    expect(results).to all(be_a(described_class::Result))
    expect(results.map(&:command)).to all(eq(results.first.command))
    expect(results.map(&:created?)).to contain_exactly(true, false)
    expect(committed_station.agent_commands.pending.where(command_type: "fetch_screens").count).to eq(1)
  end
end
