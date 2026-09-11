# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::GenerateForDateJob, type: :job do
  include ActiveJob::TestHelper

  it "delegates to GenerateForDate" do
    station = create(:station)
    allow(Playlists::GenerateForDate).to receive(:call)

    described_class.perform_now(station.id, "2026-09-02")

    expect(Playlists::GenerateForDate).to have_received(:call).with(
      station: station,
      for_date: Date.new(2026, 9, 2)
    )
  end

  it "discards when the station is gone" do
    allow(Playlists::GenerateForDate).to receive(:call)

    expect { described_class.perform_now(-1, "2026-09-02") }.not_to raise_error
    expect(Playlists::GenerateForDate).not_to have_received(:call)
  end
end
