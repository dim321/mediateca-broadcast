# frozen_string_literal: true

module MediaAssets
  class RevokeContentValidation < ServiceObject
    def initialize(media_asset:)
      @media_asset = media_asset
    end

    def call
      return media_asset unless media_asset.content_validated?

      cancel_active_orders
      rotations = strip_non_order_items
      rotations.each { |rotation| Playlists::EnqueueRegen.from_rotation(rotation) }
      media_asset
    end

    private

    attr_reader :media_asset

    def cancel_active_orders
      AdvertisingOrder.active
        .joins(rotation: :rotation_items)
        .where(rotation_items: { media_asset_id: media_asset.id })
        .distinct
        .find_each do |order|
          Advertising::CancelOrder.call(order: order)
        end
    end

    def strip_non_order_items
      items = media_asset.rotation_items.includes(rotation: :advertising_order).select do |item|
        item.rotation.advertising_order.blank?
      end
      rotations = items.map(&:rotation).uniq
      MediaAsset.transaction do
        items.each(&:destroy!)
        media_asset.update!(content_validated_at: nil, content_validated_by: nil)
      end
      rotations
    end
  end
end
