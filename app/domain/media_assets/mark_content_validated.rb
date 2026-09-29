# frozen_string_literal: true

module MediaAssets
  class MarkContentValidated < ServiceObject
    def initialize(media_asset:, user:)
      @media_asset = media_asset
      @user = user
    end

    def call
      return media_asset if media_asset.content_validated?

      raise Error, I18n.t("media_assets.content_validation.not_playable") unless playable?

      media_asset.update!(
        content_validated_at: Time.current,
        content_validated_by: user
      )
      media_asset
    end

    private

    attr_reader :media_asset, :user

    def playable?
      return false unless media_asset.ready?

      return media_asset.broadcast_ready? if media_asset.video?

      true
    end
  end
end
