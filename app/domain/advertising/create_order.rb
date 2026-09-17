# frozen_string_literal: true

module Advertising
  class CreateOrder < BaseService
    def initialize(
      organization:,
      created_by:,
      media_assets:,
      product_name:,
      placement_kind: :own_atmosphere,
      shows_per_hour: nil,
      distribution_strategy: :linear,
      coefficient_percent: 0,
      discount_cents: 0
    )
      @organization = organization
      @created_by = created_by
      @media_assets = Array(media_assets)
      @product_name = product_name
      @placement_kind = placement_kind
      @shows_per_hour = shows_per_hour
      @distribution_strategy = distribution_strategy
      @coefficient_percent = coefficient_percent
      @discount_cents = discount_cents
    end

    def call
      raise Error, I18n.t("advertising.errors.clips_required") if media_assets.empty?

      AdvertisingOrder.transaction do
        rotation = organization.rotations.create!(
          name: "order-#{SecureRandom.uuid}",
          system_managed: true
        )
        media_assets.each do |asset|
          rotation.rotation_items.create!(
            media_asset: asset,
            display_duration_seconds: asset.duration_seconds
          )
        end
        order = organization.advertising_orders.create!(
          created_by: created_by,
          media_asset: nil,
          rotation: rotation,
          product_name: product_name,
          placement_kind: placement_kind,
          shows_per_hour: shows_per_hour,
          distribution_strategy: distribution_strategy,
          coefficient_percent: coefficient_percent,
          discount_cents: discount_cents
        )
        rotation.update!(name: I18n.t("advertising.system_rotation_name", number: order.id))
        order
      end
    end

    private

    attr_reader :organization, :created_by, :media_assets, :product_name, :placement_kind,
      :shows_per_hour, :distribution_strategy, :coefficient_percent, :discount_cents
  end
end
