# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::PurgeExpiredJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  it "deletes playlists older than 14 days including superseded and keeps today (AE13)" do
    travel_to Time.utc(2026, 9, 16, 12, 0, 0) do
      old_station = create(:station)
      today_station = create(:station)
      old_current = create(:playlist, station: old_station, for_date: Date.new(2026, 9, 1), status: "current")
      old_superseded = create(
        :playlist,
        station: old_station,
        for_date: Date.new(2026, 9, 1),
        status: "superseded",
        version: 1
      )
      today = create(:playlist, station: today_station, for_date: Date.new(2026, 9, 16), status: "current")
      cutoff_day = create(:playlist, station: create(:station), for_date: Date.new(2026, 9, 2), status: "current")

      described_class.perform_now

      expect(Playlist.find_by(id: old_current.id)).to be_nil
      expect(Playlist.find_by(id: old_superseded.id)).to be_nil
      expect(Playlist.find_by(id: today.id)).to eq(today)
      expect(Playlist.find_by(id: cutoff_day.id)).to eq(cutoff_day)
    end
  end

  it "is registered as a nightly production recurring job" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    entry = config.fetch("production").fetch("purge_expired_playlists")

    expect(entry.fetch("class")).to eq("Playlists::PurgeExpiredJob")
    expect(entry.fetch("queue")).to eq("default")
    expect(entry.fetch("schedule")).to eq("at 4am every day")
  end
end
