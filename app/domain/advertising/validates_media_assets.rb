# frozen_string_literal: true

module Advertising
  module ValidatesMediaAssets
    private

    def validate_media_assets!(media_assets, organization:, medium: "video")
      assets = Array(media_assets)

      raise Error, I18n.t("advertising.errors.clips_required") if assets.empty?
      raise Error, I18n.t("advertising.errors.clips_duplicate") if assets.map(&:id).uniq.size != assets.size

      assets.each do |asset|
        raise Error, I18n.t("advertising.errors.clip_foreign") if asset.organization_id != organization.id
        raise Error, I18n.t("advertising.errors.clip_not_ready") unless asset.broadcast_ready?
        unless asset_matches_medium?(asset, medium)
          raise Error, I18n.t("advertising.errors.clip_wrong_medium", medium: medium)
        end
      end
    end

    def asset_matches_medium?(asset, medium)
      case medium.to_s
      when "audio" then asset.audio?
      when "video" then !asset.audio?
      else false
      end
    end
  end
end
