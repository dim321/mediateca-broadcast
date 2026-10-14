# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::CommandResults", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  def post_results(results, headers: agent_authorization_headers(token))
    post "/api/agent/v1/command_results", params: { results: results }, headers: headers, as: :json
  end

  def fetch_result(command, screens:, **overrides)
    {
      command_id: command.public_id,
      ok: true,
      error: nil,
      finished_at: "2026-10-09T11:01:02Z",
      result: { screens: screens }
    }.merge(overrides)
  end

  def discovered(mac_address, ip_address, **extra)
    { mac_address:, ip_address:, **extra }
  end

  def expect_rejected_discovery_result(result, public_id:)
    existing = create(:screen, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id:)

    post_results([
      fetch_result(command, screens: [], result:)
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(command.reload).to be_pending
    expect(existing.reload).to be_network_registered
  end

  it "returns 401 without a token" do
    post_results([], headers: {})

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "acks a command and drops it from the queue" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_restart_1")

    post_results([
      { command_id: "cmd_restart_1", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
    command.reload
    expect(command).to be_acked
    expect(command.succeeded).to be(true)
    expect(command.result_error).to be_nil
    expect(command.finished_at.utc.iso8601).to eq("2026-10-09T11:01:02Z")

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    expect(response.parsed_body).to eq("commands" => [])
  end

  it "treats already_done as a successful ack" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_done_locally")

    post_results([
      { command_id: "cmd_done_locally", ok: true, error: "already_done", finished_at: "2026-10-09T11:01:03Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to be_acked
    expect(command.succeeded).to be(true)
    expect(command.result_error).to eq("already_done")
  end

  it "acks a failed screenshot and removes it from pending" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_bad",
      command_type: "screenshot", params: {})

    post_results([
      { command_id: "cmd_bad", ok: false, error: "missing_upload_url", finished_at: "2026-10-09T11:01:03Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to be_acked
    expect(command.succeeded).to be(false)
    expect(command.result_error).to eq("missing_upload_url")
  end

  it "returns 200 for an unknown command id" do
    post_results([
      { command_id: "cmd_missing", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(response).not_to have_http_status(:not_found)
  end

  it "does not ack another station command" do
    foreign = create(:agent_command, public_id: "cmd_foreign")

    post_results([
      { command_id: "cmd_foreign", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(foreign.reload).to be_pending
  end

  it "returns 200 again for the same command id" do
    create(:agent_command, station:, screen:, public_id: "cmd_twice")
    body = [ { command_id: "cmd_twice", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" } ]

    post_results(body)
    post_results(body)

    expect(response).to have_http_status(:ok)
    expect(AgentCommand.find_by!(public_id: "cmd_twice").finished_at.utc.iso8601).to eq("2026-10-09T11:01:02Z")
  end

  it "synchronizes screens before acknowledging fetch_screens" do
    existing = create(
      :screen,
      station:,
      mac_address: "aa:bb:cc:dd:ee:01",
      ip_address: "192.168.1.1",
      network_registered: false
    )
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_fetch")
    screens = [
      discovered("AA-BB-CC-DD-EE-01", "192.168.1.10", name: "Injected"),
      discovered("aa:bb:cc:dd:ee:02", "192.168.1.20", arbitrary: "ignored")
    ]

    post_results([
      fetch_result(
        command,
        screens:,
        result: { screens:, extra: "ignored" },
        extra: "ignored"
      )
    ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
    expect(command.reload).to be_acked
    expect(existing.reload).to have_attributes(
      ip_address: IPAddr.new("192.168.1.10"),
      network_registered: true
    )
    expect(station.screens.order(:id).last).to have_attributes(
      mac_address: "aa:bb:cc:dd:ee:02",
      ip_address: IPAddr.new("192.168.1.20"),
      network_registered: true
    )
    expect(station.screens.order(:id).last.name).not_to eq("Injected")
  end

  it "rejects a malformed discovered MAC without changing screens or acknowledging" do
    existing = create(:screen, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_bad_mac")

    post_results([
      fetch_result(command, screens: [ { mac_address: "bad", ip_address: "192.168.1.10" } ])
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(command.reload).to be_pending
    expect(existing.reload).to be_network_registered
    expect(station.screens.count).to eq(1)
  end

  it "rejects a successful fetch_screens result without result" do
    existing = create(:screen, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_missing_result")

    post_results([
      {
        command_id: command.public_id,
        ok: true,
        error: nil,
        finished_at: "2026-10-09T11:01:02Z"
      }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(command.reload).to be_pending
    expect(existing.reload).to be_network_registered
  end

  it "rejects a successful fetch_screens result whose screens is not an array" do
    existing = create(:screen, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_bad_screens")

    post_results([ fetch_result(command, screens: { mac_address: "aa:bb:cc:dd:ee:ff" }) ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(command.reload).to be_pending
    expect(existing.reload).to be_network_registered
  end

  it "rejects a nil discovery row" do
    expect_rejected_discovery_result(
      { screens: [ nil ] },
      public_id: "cmd_nil_screen"
    )
  end

  it "rejects a scalar discovery row" do
    expect_rejected_discovery_result(
      { screens: [ "bad" ] },
      public_id: "cmd_scalar_screen"
    )
  end

  it "rejects a scalar result" do
    expect_rejected_discovery_result("bad", public_id: "cmd_scalar_result")
  end

  it "acks a failed fetch_screens result without changing registration" do
    existing = create(:screen, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_failed_fetch")

    post_results([
      {
        command_id: command.public_id,
        ok: false,
        error: "lease_file_unreadable",
        finished_at: "2026-10-09T11:01:02Z"
      }
    ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to have_attributes(
      status: "acked",
      succeeded: false,
      result_error: "lease_file_unreadable"
    )
    expect(existing.reload).to be_network_registered
  end

  it "unregisters every screen after a successful empty discovery" do
    screens = create_list(:screen, 2, station:, network_registered: true)
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_empty_fetch")

    post_results([ fetch_result(command, screens: []) ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to be_acked
    expect(screens.map(&:reload)).to all(satisfy { !_1.network_registered? })
  end

  it "does not synchronize a repeated result after the command was acknowledged" do
    command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_repeated_fetch")
    first_result = fetch_result(
      command,
      screens: [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" } ]
    )

    post_results([ first_result ])
    post_results([ fetch_result(command, screens: []) ])

    expect(response).to have_http_status(:ok)
    expect(station.screens.count).to eq(1)
    expect(station.screens.sole.reload).to be_network_registered
  end

  it "does not synchronize screens for another station command" do
    existing = create(:screen, station:, network_registered: true)
    foreign = create(:agent_command, :fetch_screens, public_id: "cmd_foreign_fetch")

    post_results([ fetch_result(foreign, screens: []) ])

    expect(response).to have_http_status(:ok)
    expect(foreign.reload).to be_pending
    expect(existing.reload).to be_network_registered
  end

  it "rejects structurally malformed discovery payloads before command lookup" do
    acknowledged = create(
      :agent_command,
      :fetch_screens,
      station:,
      public_id: "cmd_done_fetch",
      status: "acked",
      succeeded: true,
      finished_at: Time.utc(2026, 10, 9, 11, 1, 0)
    )

    post_results([
      fetch_result(acknowledged, screens: "invalid"),
      {
        command_id: "cmd_unknown_fetch",
        ok: true,
        error: nil,
        finished_at: "2026-10-09T11:01:02Z",
        result: { screens: "invalid" }
      }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(acknowledged.reload.finished_at.utc.iso8601).to eq("2026-10-09T11:01:00Z")
  end

  it "keeps a batch atomic when a later row is invalid" do
    existing = create(
      :screen,
      station:,
      mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.1.1",
      network_registered: false
    )
    fetch = create(:agent_command, :fetch_screens, station:, public_id: "cmd_atomic_fetch")
    ordinary = create(:agent_command, station:, screen: existing, public_id: "cmd_atomic_ordinary")
    allow(Agent::Screens::Synchronize).to receive(:call).and_call_original

    post_results([
      fetch_result(
        fetch,
        screens: [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" } ]
      ),
      {
        command_id: ordinary.public_id,
        ok: true,
        error: nil,
        finished_at: "invalid"
      }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(Agent::Screens::Synchronize).to have_received(:call)
    expect(fetch.reload).to be_pending
    expect(ordinary.reload).to be_pending
    expect(existing.reload).to have_attributes(
      ip_address: IPAddr.new("192.168.1.1"),
      network_registered: false
    )
  end

  it "returns 422 when finished_at is not a timestamp" do
    create(:agent_command, station:, screen:, public_id: "cmd_bad_time")

    post_results([
      { command_id: "cmd_bad_time", ok: true, error: nil, finished_at: "yesterday" }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(AgentCommand.find_by!(public_id: "cmd_bad_time")).to be_pending
  end
end
