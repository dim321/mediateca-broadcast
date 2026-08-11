# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::OccupyWithPlan do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:starts_at) { Time.utc(2026, 8, 10, 10, 0, 0) }
  let(:ends_at) { Time.utc(2026, 8, 10, 10, 10, 0) }

  before { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }

  def occupy!
    described_class.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end

  it 'creates a confirmed booking and active media plan together' do
    plan = occupy!

    expect(plan).to be_active
    expect(plan.starts_at).to eq(starts_at)
    expect(plan.ends_at).to eq(ends_at)
    expect(plan.airtime_booking).to be_confirmed
    expect(plan.airtime_booking.seconds).to eq(600)
    expect(plan.airtime_booking.organization).to eq(organization)
  end

  it 'allows adjacent non-overlapping windows' do
    occupy!
    adjacent = described_class.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: ends_at,
      ends_at: ends_at + 10.minutes
    )

    expect(adjacent).to be_active
    expect(AirtimeBooking.confirmed.count).to eq(2)
    expect(MediaPlan.active.count).to eq(2)
  end

  it 'rejects overlapping booking on the same screen without partial writes' do
    occupy!

    expect do
      described_class.call(
        organization: organization,
        broadcast_point_group: group,
        rotation: rotation,
        starts_at: starts_at + 5.minutes,
        ends_at: ends_at + 5.minutes
      )
    end.to raise_error(Airtime::ConflictError)

    expect(AirtimeBooking.confirmed.count).to eq(1)
    expect(MediaPlan.active.count).to eq(1)
  end

  it 'rejects when organization does not own the group' do
    foreign = create(:organization, :client)

    expect do
      described_class.call(
        organization: foreign,
        broadcast_point_group: group,
        rotation: create(:rotation, organization: foreign),
        starts_at: starts_at,
        ends_at: ends_at
      )
    end.to raise_error(ArgumentError, /own\/atmosphere|organization groups/)
  end

  it 'allows foreign commercial on an owner-homogeneous group' do
    owner = create(:organization, :client)
    owned_screen = create(:screen, owner_organization: owner)
    owner_group = create(:broadcast_point_group, organization: owner)
    create(:broadcast_point_group_membership, broadcast_point_group: owner_group, screen: owned_screen)
    placer = create(:organization, :client)
    placer_rotation = create(:rotation, organization: placer)

    plan = described_class.call(
      organization: placer,
      broadcast_point_group: owner_group,
      rotation: placer_rotation,
      starts_at: starts_at,
      ends_at: ends_at,
      placement_kind: :commercial,
      shows_per_hour: 2
    )

    expect(plan).to be_commercial
    expect(plan.organization).to eq(placer)
    expect(plan.broadcast_point_group).to eq(owner_group)
  end

  context "when concurrent occupies race", :concurrency do
    it 'lets only one of two overlapping occupies win (AE1)' do
      ready = Queue.new
      go = Queue.new
      outcomes = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            begin
              plan = described_class.call(
                organization: organization,
                broadcast_point_group: group,
                rotation: rotation,
                starts_at: starts_at,
                ends_at: ends_at
              )
              outcomes << [ :ok, plan.id ]
            rescue Airtime::ConflictError => e
              outcomes << [ :err, e.class.name ]
            end
          end
        end
      end

      2.times { ready.pop }
      2.times { go << true }
      threads.each(&:join)

      results = Array.new(2) { outcomes.pop }
      expect(results.count { |status, _| status == :ok }).to eq(1)
      expect(results.count { |status, _| status == :err }).to eq(1)
      expect(AirtimeBooking.confirmed.count).to eq(1)
      expect(MediaPlan.active.count).to eq(1)
    end

    it 'serializes two orgs sharing one screen (R6)' do
      org_b = create(:organization, :client)
      group_b = create(:broadcast_point_group, organization: org_b)
      create(:broadcast_point_group_membership, broadcast_point_group: group_b, screen: screen)
      rotation_b = create(:rotation, organization: org_b)

      ready = Queue.new
      go = Queue.new
      outcomes = Queue.new

      jobs = [
        [ organization, group, rotation ],
        [ org_b, group_b, rotation_b ]
      ]

      threads = jobs.map do |org, grp, rot|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            begin
              plan = described_class.call(
                organization: org,
                broadcast_point_group: grp,
                rotation: rot,
                starts_at: starts_at,
                ends_at: ends_at
              )
              outcomes << [ :ok, plan.id ]
            rescue Airtime::ConflictError => e
              outcomes << [ :err, e.class.name ]
            end
          end
        end
      end

      2.times { ready.pop }
      2.times { go << true }
      threads.each(&:join)

      results = Array.new(2) { outcomes.pop }
      expect(results.count { |status, _| status == :ok }).to eq(1)
      expect(results.count { |status, _| status == :err }).to eq(1)
      expect(AirtimeBooking.confirmed.count).to eq(1)
      expect(MediaPlan.active.count).to eq(1)
    end
  end
end
