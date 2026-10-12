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
