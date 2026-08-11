# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: media_assets
#
#  id                :bigint           not null, primary key
#  content_kind      :string           not null
#  content_type      :string           not null
#  duration_seconds  :integer
#  metadata          :jsonb            not null
#  processing_status :string           default("pending"), not null
#  visibility        :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :bigint           not null
#  uploaded_by_id    :bigint
#
# Indexes
#
#  index_media_assets_on_content_type                           (content_type)
#  index_media_assets_on_organization_id                        (organization_id)
#  index_media_assets_on_organization_id_and_created_at         (organization_id,created_at DESC)
#  index_media_assets_on_organization_id_and_processing_status  (organization_id,processing_status)
#  index_media_assets_on_uploaded_by_id                         (uploaded_by_id)
#  index_media_assets_on_visibility                             (visibility)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (uploaded_by_id => users.id) ON DELETE => nullify
#
RSpec.describe MediaAsset, type: :model do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter = :test }

  describe "validations" do
    it "requires a file on create" do
      asset = build(:media_asset)
      expect(asset).not_to be_valid
      expect(asset.errors[:file]).to be_present
    end

    it "rejects unsupported content types" do
      org = create(:organization)
      uploader = create(:user, organization: org)
      asset = build(:media_asset, organization: org, uploaded_by: uploader)
      asset.file.attach(
        io: StringIO.new("x"),
        filename: "bad.exe",
        content_type: "application/octet-stream"
      )
      expect(asset).not_to be_valid
      expect(asset.errors[:file]).to be_present
    end

    it "rejects files larger than 1 GiB" do
      asset = build(:media_asset)
      asset.file.attach(
        io: StringIO.new("x"),
        filename: "large.mp4",
        content_type: "video/mp4"
      )
      allow(asset.file).to receive(:byte_size).and_return(MediaAsset::MAX_FILE_SIZE + 1)

      expect(asset).not_to be_valid
      expect(asset.errors[:file]).to be_present
    end

    it "requires commercial content_type and visibility" do
      asset = build(:media_asset, :with_png_file, content_type: nil, visibility: nil)
      expect(asset).not_to be_valid
      expect(asset.errors[:content_type]).to be_present
      expect(asset.errors[:visibility]).to be_present
    end
  end

  describe "processing_status" do
    it "defaults to pending" do
      asset = build(:media_asset, :with_png_file)
      expect(asset.processing_status).to eq("pending")
    end
  end

  describe "associations" do
    it "belongs to organization and optional uploader" do
      org = create(:organization)
      user = create(:user, organization: org)
      asset = create(:media_asset, :with_png_file, organization: org, uploaded_by: user)
      expect(asset.organization).to eq(org)
      expect(asset.uploaded_by).to eq(user)
    end
  end

  describe "upload processing" do
    it "enqueues metadata processing after a valid upload" do
      asset = build(:media_asset, :with_png_file)

      expect { asset.save! }.to have_enqueued_job(ProcessMediaMetadataJob).with { |id| id.present? }
    end
  end

  describe "processing flash broadcast" do
    let(:organization) { create(:organization) }

    before { allow(ProcessMediaMetadataJob).to receive(:perform_later) }

    it "updates flash when status becomes ready" do
      asset = create(:media_asset, :with_png_file, organization: organization, processing_status: :processing)
      allow(asset).to receive(:broadcast_replace_to)
      allow(asset).to receive(:broadcast_update_to)

      asset.update!(processing_status: :ready, duration_seconds: 12)

      expect(asset).to have_received(:broadcast_update_to).with(
        [ organization, :media_library ],
        hash_including(
          target: "flash",
          partial: "shared/flash_alert",
          locals: hash_including(
            type: :notice,
            message: I18n.t("media_assets.create.ready")
          )
        )
      )
    end

    it "does not update flash when status becomes processing" do
      asset = create(:media_asset, :with_png_file, organization: organization, processing_status: :pending)
      allow(asset).to receive(:broadcast_replace_to)
      allow(asset).to receive(:broadcast_update_to)

      asset.update!(processing_status: :processing)

      expect(asset).not_to have_received(:broadcast_update_to)
    end
  end
end
