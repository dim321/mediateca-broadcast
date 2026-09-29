# frozen_string_literal: true

module Advertising
  class RejectOrder < BaseService
    def initialize(order:, rejection_reason:)
      @order = order
      @rejection_reason = rejection_reason.to_s
    end

    def call
      raise Error, I18n.t("advertising.errors.order_not_rejectable") unless order.draft?
      unless AdvertisingOrder.rejection_reasons.key?(rejection_reason)
        raise Error, I18n.t("advertising.errors.rejection_reason_invalid")
      end

      order.update!(status: :rejected, rejection_reason: rejection_reason)
      order
    end

    private

    attr_reader :order, :rejection_reason
  end
end
