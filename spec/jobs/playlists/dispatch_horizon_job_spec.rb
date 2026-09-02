# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::DispatchHorizonJob, type: :job do
  include ActiveJob::TestHelper

  it "enqueues a horizon job for each station" do
    first = create(:station)
    second = create(:station)

    expect { described_class.perform_now }
      .to have_enqueued_job(Playlists::GenerateStationHorizonJob).with(first.id)
      .and have_enqueued_job(Playlists::GenerateStationHorizonJob).with(second.id)
  end

  it "is registered as a production recurring job" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    entry = config.fetch("production").fetch("dispatch_playlist_horizons")

    expect(entry.fetch("class")).to eq("Playlists::DispatchHorizonJob")
    expect(entry.fetch("queue")).to eq("default")
    expect(entry.fetch("schedule")).to eq("every 15 minutes")
  end
end
