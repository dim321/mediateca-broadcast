# frozen_string_literal: true

module Advertising
  class ReplaceDraftClip < BaseService
    def initialize(order:, media_asset:)
      @order = order
      @media_asset = media_asset
    end

    def call
      validate!

      AdvertisingOrder.transaction do
        update_rotation_item
        update_order
      end

      order
    end

    private

    attr_reader :order, :media_asset

    def validate!
      raise Error, I18n.t("advertising.errors.order_not_draft") unless order.draft?
      raise Error, I18n.t("advertising.errors.clip_not_ready") unless valid_media_asset?
    end

    def valid_media_asset?
      media_asset.organization_id == order.organization_id && media_asset.broadcast_ready?
    end

    def update_rotation_item
      order.rotation.rotation_items.sole.update!(
        media_asset: media_asset,
        display_duration_seconds: media_asset.duration_seconds
      )
    end

    def update_order
      order.update!(
        media_asset: media_asset,
        clip_title: snapshot_title,
        duration_seconds: media_asset.duration_seconds
      )
    end

    def snapshot_title
      media_asset.file.filename.to_s if media_asset.file.attached?
    end
  end
end
