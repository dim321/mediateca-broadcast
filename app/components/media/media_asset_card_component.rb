# frozen_string_literal: true

module Media
  class MediaAssetCardComponent < ViewComponent::Base
    def initialize(media_asset:)
      @media_asset = media_asset
    end

    attr_reader :media_asset

    def status_badge_class
      case media_asset.processing_status
      when "ready" then "badge-success"
      when "failed" then "badge-error"
      when "processing", "pending" then "badge-warning"
      else "badge-ghost"
      end
    end
  end
end
