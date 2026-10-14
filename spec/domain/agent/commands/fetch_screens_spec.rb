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
end
