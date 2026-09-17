# frozen_string_literal: true

module Advertising
  class ReplaceDraftClip < BaseService
    def initialize(order:, media_asset:)
      @order = order
      @media_asset = media_asset
    end

    def call
      raise Error, I18n.t("advertising.errors.order_not_draft") unless order.draft?

      UpdateOrderClips.call(order: order, media_assets: [ media_asset ])
    end

    private

    attr_reader :order, :media_asset
  end
end
