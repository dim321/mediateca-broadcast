# frozen_string_literal: true

module Media
  class MediaAssetCardComponent < ViewComponent::Base
    def initialize(media_asset:)
      @media_asset = media_asset
    end

    attr_reader :media_asset

    def status_class
      case media_asset.processing_status
      when "ready" then "text-green-700"
      when "failed" then "text-red-700"
      when "processing", "pending" then "text-amber-700"
      else "text-gray-600"
      end
    end
  end
end
