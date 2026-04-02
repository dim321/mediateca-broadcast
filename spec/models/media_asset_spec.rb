# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAsset, type: :model do
  before { allow(ProcessMediaMetadataJob).to receive(:perform_later) }

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
end
