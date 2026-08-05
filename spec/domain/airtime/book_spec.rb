# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Airtime::Book do
  let(:organization) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:quota) do
    create(
      :airtime_quota,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 0, 0, 0),
      ends_at: Time.utc(2026, 8, 11, 0, 0, 0),
      seconds_total: 3_600
    )
  end
  let(:starts_at) { Time.utc(2026, 8, 10, 10, 0, 0) }
  let(:ends_at) { Time.utc(2026, 8, 10, 10, 10, 0) }

  def book!
    described_class.call(quota: quota, organization: organization, starts_at: starts_at, ends_at: ends_at)
  end

  it 'creates a confirmed booking and decrements remaining' do
    booking = book!

    expect(booking).to be_confirmed
    expect(booking.seconds).to eq(600)
    expect(booking.organization).to eq(organization)
    expect(quota.reload.seconds_remaining).to eq(3_000)
  end

  it 'rejects overflow without changing remaining (AE2)' do
    quota.update!(seconds_remaining: 600)

    expect do
      described_class.call(
        quota: quota.reload,
        organization: organization,
        starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 15, 0)
      )
    end.to raise_error(Airtime::OverflowError)

    expect(quota.reload.seconds_remaining).to eq(600)
    expect(AirtimeBooking.confirmed.count).to eq(0)
  end

  it 'allows adjacent non-overlapping windows' do
    book!
    adjacent = described_class.call(
      quota: quota.reload,
      organization: organization,
      starts_at: ends_at,
      ends_at: ends_at + 10.minutes
    )

    expect(adjacent).to be_confirmed
    expect(AirtimeBooking.confirmed.count).to eq(2)
  end

  it 'rejects overlapping booking on the same screen' do
    book!

    expect do
      described_class.call(
        quota: quota.reload,
        organization: organization,
        starts_at: starts_at + 5.minutes,
        ends_at: ends_at + 5.minutes
      )
    end.to raise_error(Airtime::ConflictError)

    expect(quota.reload.seconds_remaining).to eq(3_000)
  end

  it 'rejects when organization does not own the group' do
    foreign = create(:organization, :client)

    expect do
      described_class.call(quota: quota, organization: foreign, starts_at: starts_at, ends_at: ends_at)
    end.to raise_error(ArgumentError, /own the broadcast point group/)
  end

  context 'concurrency', :concurrency do
    it 'lets only one of two overlapping books win (AE1)' do
      ready = Queue.new
      go = Queue.new
      outcomes = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            begin
              booking = described_class.call(
                quota: quota,
                organization: organization,
                starts_at: starts_at,
                ends_at: ends_at
              )
              outcomes << [ :ok, booking.id ]
            rescue Airtime::ConflictError, Airtime::OverflowError => e
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
      expect(quota.reload.seconds_remaining).to eq(3_000)
    end

    it 'serializes two quotas sharing one screen (R6)' do
      org_b = create(:organization, :client)
      group_b = create(:broadcast_point_group, organization: org_b)
      create(:broadcast_point_group_membership, broadcast_point_group: group_b, screen: screen)
      quota_b = create(
        :airtime_quota,
        broadcast_point_group: group_b,
        starts_at: quota.starts_at,
        ends_at: quota.ends_at,
        seconds_total: 3_600
      )

      ready = Queue.new
      go = Queue.new
      outcomes = Queue.new

      jobs = [
        [ quota, organization ],
        [ quota_b, org_b ]
      ]

      threads = jobs.map do |q, org|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            go.pop
            begin
              booking = described_class.call(
                quota: q,
                organization: org,
                starts_at: starts_at,
                ends_at: ends_at
              )
              outcomes << [ :ok, booking.id ]
            rescue Airtime::ConflictError, Airtime::OverflowError => e
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
    end
  end
end
