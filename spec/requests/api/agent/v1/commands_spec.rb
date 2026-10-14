# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::Commands", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  it "returns 401 for an invalid token" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers("nope"), as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "returns an empty queue" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("commands" => [])
    expect(response.headers["ETag"]).to be_present
  end

  it "returns pending commands for this station only" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_restart_1",
      command_type: "restart_stream", params: {}, issued_at: Time.utc(2026, 10, 9, 11, 1, 0))
    create(:agent_command, public_id: "cmd_other_station")
    create(:agent_command, station:, screen:, public_id: "cmd_done", status: "acked",
      succeeded: true, finished_at: Time.utc(2026, 10, 9, 11, 2, 0))

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "commands" => [
        {
          "id" => command.public_id,
          "screen_id" => screen.id,
          "type" => "restart_stream",
          "params" => {},
          "issued_at" => "2026-10-09T11:01:00Z"
        }
      ]
    )
  end

  it "returns a station-level fetch_screens command with the exact payload" do
    command = create(
      :agent_command,
      :fetch_screens,
      station:,
      public_id: "cmd_fetch_screens",
      issued_at: Time.utc(2026, 10, 9, 11, 1, 0)
    )

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "commands" => [
        {
          "id" => command.public_id,
          "screen_id" => nil,
          "type" => "fetch_screens",
          "params" => {},
          "issued_at" => "2026-10-09T11:01:00Z"
        }
      ]
    )
  end

  it "returns 304 for an unchanged fetch_screens command" do
    create(:agent_command, :fetch_screens, station:)

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    etag = response.headers["ETag"]

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => etag)

    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  it "returns 304 when If-None-Match repeats the queue etag" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    etag = response.headers["ETag"]

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => etag)

    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  it "returns 200 when If-None-Match is empty even if the queue is unchanged" do
    create(:agent_command, station:, screen:, public_id: "cmd_visible")

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => ""),
      as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["commands"].map { |row| row["id"] }).to eq([ "cmd_visible" ])
  end

  it "returns 200 when If-None-Match is a weak tag" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    etag = response.headers["ETag"]

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => "W/#{etag}"),
      as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key("commands")
  end

  it "returns 200 when If-None-Match is a comma-separated list" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    etag = response.headers["ETag"]

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => "#{etag}, \"other\""),
      as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key("commands")
  end
end
