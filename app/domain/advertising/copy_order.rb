# frozen_string_literal: true

module Advertising
  # Новый черновик с атрибутами источника. Дни сетки и период С/По не копируются.
  class CopyOrder < BaseService
    def initialize(source:, created_by:)
      @source = source
      @created_by = created_by
    end

    def call
      AdvertisingOrder.transaction do
        order = CreateOrder.call(
          organization: source.organization,
          created_by: created_by,
          media_assets: source_media_assets,
          product_name: source.product_name,
          placement_kind: source.placement_kind,
          shows_per_hour: source.shows_per_hour,
          distribution_strategy: source.distribution_strategy,
          coefficient_percent: source.coefficient_percent,
          discount_cents: source.discount_cents
        )
        copy_snapshot_attributes!(order)
        copy_windows!(order)
        copy_screens!(order)
        order
      end
    end

    private

    attr_reader :source, :created_by

    def source_media_assets
      source.rotation.ordered_items.filter_map(&:media_asset)
    end

    def copy_snapshot_attributes!(order)
      order.business_sphere = source.business_sphere if source.business_sphere.present?
      order.clip_title = source.clip_title if source.clip_title.present?
      order.duration_seconds = source.duration_seconds if source.duration_seconds.present?
      order.save! if order.changed?
    end

    def copy_windows!(order)
      source.advertising_order_windows.order(:id).each do |window|
        order.advertising_order_windows.create!(starts_at: window.starts_at, ends_at: window.ends_at)
      end
    end

    def copy_screens!(order)
      source.advertising_order_lines.order(:id).each do |line|
        order.advertising_order_lines.create!(
          screen: line.screen,
          price_per_day_cents: line.price_per_day_cents
        )
      end
    end
  end
end
