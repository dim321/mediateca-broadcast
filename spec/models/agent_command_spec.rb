# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentCommand, type: :model do
  describe "command types" do
    it "separates screen and station commands" do
      expect(described_class::SCREEN_TYPES).not_to include("fetch_screens")
      expect(described_class::STATION_TYPES).to eq(%w[fetch_screens])
      expect(described_class::TYPES).to contain_exactly(
        *described_class::SCREEN_TYPES,
        *described_class::STATION_TYPES
      )
    end
  end

  describe "command scope" do
    it "allows fetch_screens without a screen" do
      expect(build(:agent_command, :fetch_screens)).to be_valid
    end

    it "rejects a screen command without a screen" do
      command = build(:agent_command, screen: nil)

      expect(command).not_to be_valid
      expect(command.errors[:screen]).to be_present
    end

    it "rejects fetch_screens with a screen" do
      command = build(:agent_command, :fetch_screens, screen: create(:screen))

      expect(command).not_to be_valid
      expect(command.errors[:screen]).to be_present
    end

    it "rejects a screen from another station" do
      command = build(:agent_command, screen: create(:screen))

      expect(command).not_to be_valid
      expect(command.errors[:screen]).to be_present
    end
  end

  describe "pending fetch_screens uniqueness" do
    it "allows only one pending command per station at the database level" do
      station = create(:station)
      create(:agent_command, :fetch_screens, station: station)

      expect do
        create(:agent_command, :fetch_screens, station: station)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
