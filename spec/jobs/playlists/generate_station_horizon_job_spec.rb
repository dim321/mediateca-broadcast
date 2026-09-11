# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::GenerateStationHorizonJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  it "generates each date in the station horizon inline" do
    location = create(:location, time_zone: "UTC")
    station = create(:station, location: location, offline_cache_hours: 24)
    allow(Playlists::GenerateForDate).to receive(:call)

    travel_to Time.utc(2026, 9, 2, 12, 0, 0) do
      described_class.perform_now(station.id)
    end

    expect(Playlists::GenerateForDate).to have_received(:call).with(station: station, for_date: Date.new(2026, 9, 2))
    expect(Playlists::GenerateForDate).to have_received(:call).with(station: station, for_date: Date.new(2026, 9, 3))
  end

  it "discards when the station is gone" do
    allow(Playlists::GenerateForDate).to receive(:call)

    expect { described_class.perform_now(-1) }.not_to raise_error
    expect(Playlists::GenerateForDate).not_to have_received(:call)
  end

  it "limits concurrency to one job per station when Solid Queue supports it" do
    skip "limits_concurrency is not on ApplicationJob" unless described_class.respond_to?(:limits_concurrency)

    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_on_conflict).to eq(:discard)
  end
end
