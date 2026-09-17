# frozen_string_literal: true

module Advertising
  class UpdateOrderClips < BaseService
    include ValidatesMediaAssets

    def initialize(order:, media_assets:)
      @order = order
      @media_assets = Array(media_assets)
    end

    def call
      validate_order_status!
      validate_media_assets!(media_assets, organization: order.organization)

      AdvertisingOrder.transaction do
        sync_rotation_items
        update_order!
      end

      enqueue_regen if order.active?
      order
    end

    private

    attr_reader :order, :media_assets

    def validate_order_status!
      return if order.draft? || order.active?

      raise Error, I18n.t("advertising.errors.order_clips_not_editable")
    end

    def sync_rotation_items
      rotation = order.rotation
      rotation.rotation_items.destroy_all
      media_assets.each do |asset|
        rotation.rotation_items.create!(
          media_asset: asset,
          display_duration_seconds: asset.duration_seconds
        )
      end
    end

    def update_order!
      attrs = { media_asset_id: nil }
      attrs[:document_version] = order.document_version + 1 if order.active?
      order.update!(attrs)
    end

    def enqueue_regen
      order.rotation.media_plans.active.find_each { |plan| Playlists::EnqueueRegen.from_plan(plan) }
    end
  end
end
