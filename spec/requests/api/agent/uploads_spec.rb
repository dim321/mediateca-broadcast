# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::Uploads", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  after { travel_back }

  let(:command) { create(:agent_command, command_type: "screenshot", params: {}) }

  def put_artifact(token:, body:, content_type:)
    put "/api/agent/uploads/#{token}",
      params: body,
      headers: { "CONTENT_TYPE" => content_type }
  end

  it "stores a png without a bearer token" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "png-bytes", content_type: "image/png")

    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("png-bytes")
    expect(command.artifact.content_type).to eq("image/png")
    expect(command.artifact.filename.to_s).to eq("screenshot.png")
  end

  it "replaces the blob when the station retries the put" do
    token = Agent::ArtifactToken.generate(command.public_id)
    put_artifact(token:, body: "first", content_type: "image/png")
    put_artifact(token:, body: "second", content_type: "image/png")

    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("second")
  end

  it "returns 403 for a bad token and does not use 401" do
    put_artifact(token: "not-a-token", body: "png-bytes", content_type: "image/png")

    expect(response).to have_http_status(:forbidden)
    expect(response).not_to have_http_status(:unauthorized)
  end

  it "returns 403 for an expired token and does not use 401" do
    token = Agent::ArtifactToken.generate(command.public_id)
    travel 16.minutes

    put_artifact(token:, body: "png-bytes", content_type: "image/png")

    expect(response).to have_http_status(:forbidden)
    expect(response).not_to have_http_status(:unauthorized)
    expect(command.reload.artifact).not_to be_attached
  end

  it "returns 413 when the body exceeds the size limit" do
    stub_const("Agent::StoreArtifact::MAX_BYTES", 4)
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "12345", content_type: "image/png")

    expect(response).to have_http_status(:content_too_large)
    expect(command.reload.artifact).not_to be_attached
  end

  it "returns 415 when the content type does not match the command" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "png-bytes", content_type: "text/plain")

    expect(response).to have_http_status(:unsupported_media_type)
    expect(command.reload.artifact).not_to be_attached
  end

  it "returns 422 for an empty body" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "", content_type: "image/png")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "empty_body")
  end

  it "stores an mp4 for a record command" do
    record = create(:agent_command, command_type: "record", params: { "seconds" => 15 })
    token = Agent::ArtifactToken.generate(record.public_id)

    put_artifact(token:, body: "mp4-bytes", content_type: "video/mp4")

    expect(response).to have_http_status(:no_content)
    expect(record.reload.artifact.download).to eq("mp4-bytes")
    expect(record.artifact.filename.to_s).to eq("record.mp4")
    expect(record.artifact.content_type).to eq("video/mp4")
  end
end
