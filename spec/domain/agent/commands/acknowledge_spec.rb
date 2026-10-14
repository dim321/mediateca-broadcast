# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe Agent::Commands::Acknowledge, :concurrency do
  let!(:location) { create(:location) }
  let!(:station) { create(:station, location:) }
  let!(:command) do
    create(:agent_command, :fetch_screens, station:, public_id: "cmd_concurrent_fetch")
  end

  let(:first_screens) do
    [
      discovered("aa:bb:cc:dd:ee:01", "192.168.1.10"),
      discovered("aa:bb:cc:dd:ee:02", "192.168.1.11")
    ]
  end

  let(:second_screens) do
    [
      discovered("aa:bb:cc:dd:ee:03", "192.168.1.20"),
      discovered("aa:bb:cc:dd:ee:04", "192.168.1.21")
    ]
  end

  it "serializes concurrent successful results for the same command" do
    entered_sync = Queue.new
    release_sync = Queue.new
    outcomes = Queue.new
    synchronized_payloads = []
    payloads_lock = Mutex.new
    original_sync = Agent::Screens::Synchronize.method(:call)

    allow(Agent::Screens::Synchronize).to receive(:call) do |**arguments|
      entered_sync << arguments.fetch(:screens)
      release_sync.pop
      original_sync.call(**arguments)
      payloads_lock.synchronize { synchronized_payloads << arguments.fetch(:screens) }
    end

    first = acknowledge_in_thread(first_screens, outcomes:, finished_at: "2026-10-09T11:01:02Z")
    expect(Timeout.timeout(5) { entered_sync.pop }).to eq(first_screens)

    second_pid = Queue.new
    second = acknowledge_in_thread(
      second_screens,
      outcomes:,
      pid: second_pid,
      finished_at: "2026-10-09T11:01:03Z"
    )
    raced_payload = wait_for_lock_or_second_sync(second_pid.pop, entered_sync)

    release_sync << true
    first.join
    release_sync << true if raced_payload
    second.join

    results = Array.new(2) { outcomes.pop }
    expect(results).to eq([ :ok, :ok ])
    expect(raced_payload).to be_nil
    expect(synchronized_payloads).to eq([ first_screens ])
    expect(command.reload).to be_acked
    expect(command.finished_at.utc.iso8601).to eq("2026-10-09T11:01:02Z")
    expect(station.screens.order(:mac_address).pluck(:mac_address).map(&:to_s)).to eq(
      %w[aa:bb:cc:dd:ee:01 aa:bb:cc:dd:ee:02]
    )
    expect(station.screens.count).to eq(2)
  ensure
    2.times { release_sync << true } if release_sync
    first&.join
    second&.join
  end

  private

  def discovered(mac_address, ip_address)
    { "mac_address" => mac_address, "ip_address" => ip_address }
  end

  def acknowledge_in_thread(screens, outcomes:, finished_at:, pid: nil)
    station_id = station.id
    command_id = command.public_id

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        pid << connection.select_value("SELECT pg_backend_pid()") if pid
        described_class.call(
          station: Station.find(station_id),
          results: [ result_row(screens, command_id:, finished_at:) ]
        )
        outcomes << :ok
      rescue StandardError => error
        outcomes << error
      end
    end
  end

  def result_row(screens, command_id:, finished_at:)
    {
      command_id:,
      ok: true,
      error: nil,
      finished_at:,
      result: { screens: }
    }
  end

  def wait_for_lock_or_second_sync(pid, entered_sync)
    Timeout.timeout(5) do
      loop do
        return entered_sync.pop(true)
      rescue ThreadError
        return if waiting_on_lock?(pid)

        Thread.pass
      end
    end
  end

  def waiting_on_lock?(pid)
    ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT EXISTS (
        SELECT 1
        FROM pg_stat_activity
        WHERE pid = #{Integer(pid)}
          AND wait_event_type = 'Lock'
      )
    SQL
  end
end
