# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessMediaMetadataJob, type: :job do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  before { ActiveJob::Base.queue_adapter = :test }

  it "marks asset ready with extractor output" do
    allow(described_class).to receive(:perform_later)
    asset = create(:media_asset, :with_png_file, organization: organization, uploaded_by: user)

    result = Media::MetadataExtractor::Result.new(
      duration_seconds: nil,
      metadata: { "probe" => "ok" },
      refined_content_kind: "image"
    )
    allow(Media::MetadataExtractor).to receive(:call).and_return(result)
    allow(Media::PreviewGenerator).to receive(:call)

    described_class.perform_now(asset.id)

    asset.reload
    expect(asset).to be_ready
    expect(asset.metadata).to include("probe" => "ok")
  end

  it "marks failed when processing raises" do
    allow(described_class).to receive(:perform_later)
    asset = create(:media_asset, :with_png_file, organization: organization, uploaded_by: user)
    allow(Media::MetadataExtractor).to receive(:call).and_raise(StandardError, "boom")
    allow(Media::PreviewGenerator).to receive(:call)

    described_class.perform_now(asset.id)

    asset.reload
    expect(asset).to be_failed
    expect(asset.metadata["error"]).to eq("boom")
  end

  it "queues video transcoding after metadata extraction" do
    allow(described_class).to receive(:perform_later)
    asset = build(:media_asset, organization: organization, uploaded_by: user)
    asset.file.attach(
      io: StringIO.new("source video"),
      filename: "source.mp4",
      content_type: "video/mp4"
    )
    asset.save!
    result = Media::MetadataExtractor::Result.new(
      duration_seconds: 30,
      metadata: { "probe" => "ok" },
      refined_content_kind: "video"
    )
    allow(Media::MetadataExtractor).to receive(:call).and_return(result)
    allow(Media::PreviewGenerator).to receive(:call)

    expect { described_class.perform_now(asset.id) }
      .to have_enqueued_job(MediaTranscodeJob).with(asset.id)

    expect(asset.reload).to be_processing
  end
end
