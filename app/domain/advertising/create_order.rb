# frozen_string_literal: true

module Advertising
  class CreateOrder < BaseService
    def initialize(
      organization:,
      created_by:,
      media_asset:,
      product_name:,
      placement_kind: :own_atmosphere,
      coefficient_percent: 0,
      discount_cents: 0
    )
      @organization = organization
      @created_by = created_by
      @media_asset = media_asset
      @product_name = product_name
      @placement_kind = placement_kind
      @coefficient_percent = coefficient_percent
      @discount_cents = discount_cents
    end

    def call
      AdvertisingOrder.transaction do
        rotation = organization.rotations.create!(
          name: "order-#{SecureRandom.uuid}",
          system_managed: true
        )
        rotation.rotation_items.create!(
          media_asset: media_asset,
          display_duration_seconds: media_asset.duration_seconds
        )
        order = organization.advertising_orders.create!(
          created_by: created_by,
          media_asset: media_asset,
          rotation: rotation,
          product_name: product_name,
          placement_kind: placement_kind,
          coefficient_percent: coefficient_percent,
          discount_cents: discount_cents
        )
        rotation.update!(name: I18n.t("advertising.system_rotation_name", number: order.id))
        order
      end
    end

    private

    attr_reader :organization, :created_by, :media_asset, :product_name, :placement_kind,
      :coefficient_percent, :discount_cents
  end
end
