# frozen_string_literal: true

class ProcessMediaMetadataJob < ApplicationJob
  queue_as :default

  def perform(media_asset_id)
    media_asset = MediaAsset.find_by(id: media_asset_id)
    return if media_asset.blank?
    return unless media_asset.file.attached?

    media_asset.update!(processing_status: :processing)

    media_asset.file.blob.open(tmpdir: Dir.tmpdir) do |tmpfile|
      path = tmpfile.path
      result = Media::MetadataExtractor.call(path, declared_content_type: media_asset.file.content_type)
      Media::PreviewGenerator.call(media_asset, path)
      media_asset.reload

      attrs = {
        processing_status: :ready,
        duration_seconds: result.duration_seconds,
        metadata: media_asset.metadata.merge(result.metadata)
      }
      if result.refined_content_kind.present?
        attrs[:content_kind] = result.refined_content_kind
      end
      media_asset.update!(attrs)
    end
  rescue StandardError => e
    handle_failure(media_asset_id, e)
  end

  private

  def handle_failure(media_asset_id, error)
    media_asset = MediaAsset.find_by(id: media_asset_id)
    return if media_asset.blank?

    meta = media_asset.metadata.merge(
      "error" => error.message,
      "error_class" => error.class.name
    )
    media_asset.update!(processing_status: :failed, metadata: meta)
  end
end
