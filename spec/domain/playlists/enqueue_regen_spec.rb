# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::EnqueueRegen do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def build_station(time_zone: "UTC", cache_hours: 24)
    location = create(:location, time_zone: time_zone)
    create(:station, location: location, offline_cache_hours: cache_hours)
  end

  def plan_on(station, starts_at:, ends_at:)
    screen = create(:screen, station: station)
    organization = create(:organization, :client)
    group = create(:broadcast_point_group, organization: organization)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    create(
      :media_plan,
      organization: organization,
      broadcast_point_group: group,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  around do |example|
    travel_to(Time.utc(2026, 9, 2, 12, 0, 0), &example)
  end

  it "enqueues GenerateForDateJob for unique in-horizon dates and does not generate inline" do
    station = build_station
    allow(Playlists::GenerateForDate).to receive(:call)

    expect {
      described_class.call(
        station_ids: [ station.id, station.id ],
        dates: [ Date.new(2026, 9, 1), Date.new(2026, 9, 2), Date.new(2026, 9, 2), Date.new(2026, 9, 4) ]
      )
    }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-02").exactly(:once)

    expect(Playlists::GenerateForDate).not_to have_received(:call)
  end

  it "includes today and tomorrow when offline_cache_hours is 24" do
    station = build_station(cache_hours: 24)

    expect { described_class.from_station(station) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-02")
      .and have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-03")
  end

  it "uses the station location time zone for today" do
    station = build_station(time_zone: "Asia/Kamchatka")
    # 2026-09-02 12:00 UTC == 2026-09-03 00:00 in Asia/Kamchatka (UTC+12)
    expect { described_class.from_station(station) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-03")
      .and have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-04")
  end

  it "enqueues overlapping local dates from a plan, clamped to the horizon" do
    station = build_station
    plan = plan_on(
      station,
      starts_at: Time.utc(2026, 9, 3, 10, 0, 0),
      ends_at: Time.utc(2026, 9, 3, 11, 0, 0)
    )

    expect { described_class.from_plan(plan) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-03").exactly(:once)
  end

  it "dedups two screens of the same station on from_plan" do
    station = build_station
    plan = plan_on(station, starts_at: Time.utc(2026, 9, 3, 10, 0, 0), ends_at: Time.utc(2026, 9, 3, 11, 0, 0))
    extra = create(:screen, station: station)
    create(:broadcast_point_group_membership, broadcast_point_group: plan.broadcast_point_group, screen: extra)

    expect { described_class.from_plan(plan) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-03").exactly(:once)
  end

  it "skips past-only plan windows" do
    station = build_station
    plan = plan_on(station, starts_at: Time.utc(2026, 8, 10, 10, 0, 0), ends_at: Time.utc(2026, 8, 10, 11, 0, 0))

    expect { described_class.from_plan(plan) }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
  end

  it "enqueues every station at a location" do
    location = create(:location, time_zone: "UTC")
    first = create(:station, location: location, offline_cache_hours: 24)
    second = create(:station, location: location, offline_cache_hours: 24)

    expect { described_class.from_location(location) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(first.id, "2026-09-02")
      .and have_enqueued_job(Playlists::GenerateForDateJob).with(second.id, "2026-09-02")
  end

  it "enqueues the screen station horizon" do
    station = build_station
    screen = create(:screen, station: station)

    expect { described_class.from_screen(screen) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-02")
  end

  it "enqueues stations whose portraits reference the rotation" do
    station = build_station
    rotation = create(:rotation)
    portrait = create(:broadcast_portrait, :for_screen, screen: create(:screen, station: station))
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, rotation: rotation)

    expect { described_class.from_rotation(rotation) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-02")
  end

  it "enqueues only stations with inheriting screens from location hours" do
    location = create(:location, time_zone: "UTC")
    inheriting = create(:station, location: location, offline_cache_hours: 24)
    custom = create(:station, location: location, offline_cache_hours: 24)
    create(:screen, station: inheriting, inherit_operating_hours_from_location: true)
    create(:screen, station: custom, inherit_operating_hours_from_location: false,
      operating_hours: { "wed" => [ { "start" => "10:00", "end" => "20:00" } ] })

    expect { described_class.from_location_hours(location) }
      .to have_enqueued_job(Playlists::GenerateForDateJob).with(inheriting.id, "2026-09-02")
    expect { described_class.from_location_hours(location) }
      .not_to have_enqueued_job(Playlists::GenerateForDateJob).with(custom.id, "2026-09-02")
  end
end
