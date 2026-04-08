# frozen_string_literal: true

module Playback
  class MediaUrlPresenter
    def self.call(media_asset)
      new(media_asset).call
    end

    def initialize(media_asset)
      @media_asset = media_asset
    end

    def call
      {
        id: media_asset.id,
        url: signed_blob_url,
        mime_type: media_asset.file.blob&.content_type
      }
    end

    private

    attr_reader :media_asset

    def signed_blob_url
      return nil unless media_asset.file.attached?

      Rails.application.routes.url_helpers.rails_blob_path(
        media_asset.file,
        disposition: "inline",
        only_path: true
      )
    end
  end
end
