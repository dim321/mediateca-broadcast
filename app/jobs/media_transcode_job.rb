# frozen_string_literal: true

require "tempfile"

class MediaTranscodeJob < ApplicationJob
  queue_as :default

  def perform(media_asset_id)
    media_asset = MediaAsset.find_by(id: media_asset_id)
    return if media_asset.blank? || !media_asset.video?
    return if media_asset.broadcast_file.attached?

    media_asset.update!(processing_status: :processing)

    media_asset.file.blob.open(tmpdir: Dir.tmpdir) do |input_file|
      Tempfile.create([ "broadcast", ".ts" ]) do |output_file|
        output_file.close
        Media::TsEncoder.call(input_file.path, output_file.path)
        attach_broadcast_file(media_asset, output_file.path)
      end
    end

    media_asset.update!(processing_status: :ready)
  rescue StandardError => e
    handle_failure(media_asset_id, e)
  end

  private

  def attach_broadcast_file(media_asset, path)
    File.open(path, "rb") do |output_file|
      media_asset.broadcast_file.attach(
        io: output_file,
        filename: "#{media_asset.file.filename.base}.ts",
        content_type: "video/mp2t"
      )
    end
  end

  def handle_failure(media_asset_id, error)
    media_asset = MediaAsset.find_by(id: media_asset_id)
    return if media_asset.blank?

    media_asset.update!(
      processing_status: :failed,
      metadata: media_asset.metadata.merge(
        "transcode_error" => error.message,
        "transcode_error_class" => error.class.name
      )
    )
  end
end
