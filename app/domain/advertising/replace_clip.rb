# frozen_string_literal: true

module Advertising
  class ReplaceClip < BaseService
    def initialize(order:, media_asset:)
      @order = order
      @media_asset = media_asset
    end

    def call
      raise Error, I18n.t("advertising.errors.order_not_active") unless order.active?
      raise Error, I18n.t("advertising.errors.clip_not_ready") unless media_asset.broadcast_ready?

      AdvertisingOrder.transaction do
        item = order.rotation.rotation_items.sole
        item.update!(
          media_asset: media_asset,
          display_duration_seconds: media_asset.duration_seconds
        )
        order.update!(
          media_asset: media_asset,
          clip_title: snapshot_title,
          duration_seconds: media_asset.duration_seconds,
          document_version: order.document_version + 1
        )
      end
      order
    end

    private

    attr_reader :order, :media_asset

    def snapshot_title
      media_asset.file.filename.to_s if media_asset.file.attached?
    end
  end
end
