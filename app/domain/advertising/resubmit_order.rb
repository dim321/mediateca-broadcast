# frozen_string_literal: true

module Advertising
  class ResubmitOrder < BaseService
    def initialize(order:)
      @order = order
    end

    def call
      raise Error, I18n.t("advertising.errors.order_not_resubmittable") unless order.rejected?

      order.update!(status: :draft, rejection_reason: nil)
      order
    end

    private

    attr_reader :order
  end
end
