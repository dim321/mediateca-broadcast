# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::Telemetries", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let!(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  def payload(screen_id: screen.id, reported_at: "2026-10-09T11:00:00Z")
    {
      reported_at: reported_at,
      station: {
        uptime_seconds: 3600,
        package_etag: "W/\"pkg\"",
        broadcast_ok: true
      },
      screens: [
        {
          screen_id: screen_id,
          reachable: true,
          agent_ok: true,
          playing: true,
          url: "http://192.168.33.1:8091/",
          wakefulness: "",
          stream_port: 8091,
          broadcast_clients: 0,
          last_error: nil
        }
      ]
    }
  end

  it "returns 401 without a token" do
    post "/api/agent/v1/telemetry", params: payload, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "accepts an empty wakefulness and a zero client count" do
    post "/api/agent/v1/telemetry", params: payload, headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.body).to be_empty
    snapshot = station.reload.telemetry_snapshot
    expect(snapshot.package_etag).to eq("W/\"pkg\"")
    expect(snapshot.broadcast_ok).to be(true)
    screen_snapshot = screen.reload.telemetry_snapshot
    expect(screen_snapshot.wakefulness).to eq("")
    expect(screen_snapshot.broadcast_clients).to eq(0)
    expect(screen_snapshot.last_error).to be_nil
    expect(screen_snapshot.playing).to be(true)
  end

  it "does not wrap the unrooted JSON body under :telemetry" do
    unpermitted = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      unpermitted.concat(Array(payload[:keys]))
    end

    ActiveSupport::Notifications.subscribed(callback, "unpermitted_parameters.action_controller") do
      post "/api/agent/v1/telemetry", params: payload, headers: agent_authorization_headers(token), as: :json
    end

    expect(response).to have_http_status(:accepted)
    expect(unpermitted).not_to include(:telemetry)
  end

  it "keeps the batch when a screen id belongs to another station" do
    other = create(:screen)

    post "/api/agent/v1/telemetry",
      params: payload(screen_id: other.id),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:accepted)
    expect(station.reload.telemetry_snapshot.ignored_screen_ids).to eq([ other.id ])
    expect(other.reload.telemetry_snapshot).to be_nil
    expect(screen.reload.telemetry_snapshot).to be_nil
  end

  it "does not overwrite a newer snapshot with an older reported_at" do
    post "/api/agent/v1/telemetry",
      params: payload(reported_at: "2026-10-09T12:00:00Z"),
      headers: agent_authorization_headers(token),
      as: :json
    post "/api/agent/v1/telemetry",
      params: payload(reported_at: "2026-10-09T11:00:00Z"),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:accepted)
    expect(station.reload.telemetry_snapshot.reported_at.utc.iso8601).to eq("2026-10-09T12:00:00Z")
  end

  it "returns 422 when uptime_seconds is invalid" do
    post "/api/agent/v1/telemetry",
      params: payload.deep_merge(station: { uptime_seconds: -1 }),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_telemetry")
    expect(station.reload.telemetry_snapshot).to be_nil
  end

  it "returns 422 when reported_at is missing" do
    post "/api/agent/v1/telemetry",
      params: payload.except(:reported_at),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_telemetry")
  end

  it "returns 422 when the screens key is missing" do
    post "/api/agent/v1/telemetry",
      params: payload.except(:screens),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_telemetry")
  end

  it "accepts an empty screens array for a station with no screens" do
    screenless_token = SecureRandom.hex(16)
    screenless_station = create(:station)
    screenless_station.assign_agent_token!(screenless_token)

    post "/api/agent/v1/telemetry",
      params: {
        reported_at: "2026-10-09T11:00:00Z",
        station: {
          uptime_seconds: 120,
          package_etag: "W/\"empty\"",
          broadcast_ok: false
        },
        screens: []
      },
      headers: agent_authorization_headers(screenless_token),
      as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.body).to be_empty
    snapshot = screenless_station.reload.telemetry_snapshot
    expect(snapshot).to be_present
    expect(snapshot.package_etag).to eq("W/\"empty\"")
    expect(snapshot.broadcast_ok).to be(false)
  end
end
