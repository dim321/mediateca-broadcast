# frozen_string_literal: true

require "fileutils"
require "rails_helper"

RSpec.describe MediaTranscodeJob, type: :job do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  before { ActiveJob::Base.queue_adapter = :test }

  it "attaches a broadcast file and marks a video ready" do
    asset = create_video_asset
    allow(Media::TsEncoder).to receive(:call) do |_input_path, output_path|
      FileUtils.cp(Rails.root.join("spec/fixtures/files/broadcast.ts"), output_path)
    end

    described_class.perform_now(asset.id)

    asset.reload
    expect(asset).to be_ready
    expect(asset.broadcast_file).to be_attached
    expect(asset.broadcast_file.content_type).to eq("video/mp2t")
  end

  it "leaves non-video assets ready without transcoding" do
    asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
    allow(Media::TsEncoder).to receive(:call)

    described_class.perform_now(asset.id)

    asset.reload
    expect(asset).to be_ready
    expect(asset.broadcast_file).not_to be_attached
    expect(Media::TsEncoder).not_to have_received(:call)
  end

  it "does not mark the asset failed on the first storage timeout" do
    asset = create_video_asset
    clear_enqueued_jobs
    allow(MediaAsset).to receive(:find_by).with(id: asset.id).and_return(asset)
    allow(asset.file.blob).to receive(:open).and_raise(
      Errno::ETIMEDOUT, "user specified timeout for 192.168.1.14:9010"
    )

    expect { described_class.perform_now(asset.id) }.to have_enqueued_job(described_class)
    expect(asset.reload).not_to be_failed
  end

  it "marks the asset failed with transcode error metadata when encoding fails" do
    asset = create_video_asset
    allow(Media::TsEncoder).to receive(:call).and_raise(Media::TsEncoder::EncodingError, "encoder failed")

    described_class.perform_now(asset.id)

    asset.reload
    expect(asset).to be_failed
    expect(asset.metadata).to include(
      "transcode_error" => "encoder failed",
      "transcode_error_class" => "Media::TsEncoder::EncodingError"
    )
    expect(asset.broadcast_file).not_to be_attached
  end

  private

  def create_video_asset
    asset = build(:media_asset, organization: organization, uploaded_by: user)
    asset.file.attach(
      io: StringIO.new("source video"),
      filename: "source.mp4",
      content_type: "video/mp4"
    )
    asset.save!
    asset
  end
end
