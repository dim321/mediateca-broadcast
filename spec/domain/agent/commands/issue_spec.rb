# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Commands::Issue do
  let(:screen) { create(:screen) }
  let(:url_options) { { host: "hub.example", protocol: "https" } }

  it "queues a restart_stream with an empty params object" do
    command = described_class.call(screen:, type: "restart_stream", params: {}, url_options:)

    expect(command).to be_pending
    expect(command.public_id).to start_with("cmd_")
    expect(command.screen).to eq(screen)
    expect(command.station).to eq(screen.station)
    expect(command.params).to eq({})
    expect(command.command_type).to eq("restart_stream")
    expect(command.issued_at).to be_present
  end

  it "puts a signed upload url on screenshot and ignores a caller-supplied one" do
    command = described_class.call(
      screen:,
      type: "screenshot",
      params: { "upload_url" => "https://evil.example/put" },
      url_options:
    )

    expect(command.params.keys).to eq([ "upload_url" ])
    expect(command.params["upload_url"]).to start_with("https://hub.example/api/agent/uploads/")
    expect(command.params["upload_url"]).not_to include("evil.example")
    token = command.params["upload_url"].split("/").last
    expect(Agent::ArtifactToken.verify!(CGI.unescape(token))).to eq(command.public_id)
  end

  it "defaults record length to 10 seconds" do
    command = described_class.call(screen:, type: "record", params: {}, url_options:)

    expect(command.params["seconds"]).to eq(10)
    expect(command.params["upload_url"]).to be_present
  end

  it "stores an explicit record length" do
    command = described_class.call(screen:, type: "record", params: { seconds: 15 }, url_options:)

    expect(command.params["seconds"]).to eq(15)
    expect(command.params["upload_url"]).to be_present
  end

  it "rejects a record longer than 120 seconds" do
    expect {
      described_class.call(screen:, type: "record", params: { seconds: 121 }, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("seconds_out_of_range") }
  end

  it "rejects an install_apk url that is not https" do
    expect {
      described_class.call(screen:, type: "install_apk", params: { url: "http://files.example/app.apk" }, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("url_must_be_https") }
  end

  it "rejects an unknown type" do
    expect {
      described_class.call(screen:, type: "reboot_station", params: {}, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("unknown_type") }
  end

  it "rejects a station command for a screen" do
    expect {
      described_class.call(screen:, type: "fetch_screens", params: {}, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("unknown_type") }
  end

  it "refuses to mint an upload url without a host" do
    expect {
      described_class.call(screen:, type: "screenshot", params: {}, url_options: {})
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("missing_host") }
  end
end
