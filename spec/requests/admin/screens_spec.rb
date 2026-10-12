# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin screen agent commands", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { sign_in_as(operator) }

  it "queues a restart_stream that the agent poll can see" do
    token = SecureRandom.hex(16)
    station.assign_agent_token!(token)

    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "restart_stream", url: "", buffer_ms: "", seconds: "" }
    }

    expect(response).to redirect_to(admin_screen_path(screen))
    command = screen.agent_commands.pending.sole
    expect(command.command_type).to eq("restart_stream")
    expect(command.params).to eq({})

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    expect(response.parsed_body["commands"].map { |row| row["id"] }).to eq([ command.public_id ])
  end

  it "queues a screenshot whose upload url is on this host" do
    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "screenshot", url: "https://evil.example/put", buffer_ms: "", seconds: "" }
    }

    command = screen.agent_commands.pending.sole
    expect(command.params["upload_url"]).to include("/api/agent/uploads/")
    expect(command.params["upload_url"]).not_to include("evil.example")

    token = command.params["upload_url"].split("/uploads/").last
    put "/api/agent/uploads/#{token}", params: "png-bytes", headers: { "CONTENT_TYPE" => "image/png" }
    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("png-bytes")
  end

  it "rejects a non-https apk url and leaves the queue empty" do
    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "install_apk", url: "http://files.example/app.apk", buffer_ms: "", seconds: "" }
    }

    expect(response).to redirect_to(admin_screen_path(screen))
    expect(screen.agent_commands).to be_empty
    follow_redirect!
    expect(response.body).to include(I18n.t("admin.agent_commands.errors.url_must_be_https"))
  end
end
