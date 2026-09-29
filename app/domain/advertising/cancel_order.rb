# frozen_string_literal: true

module Advertising
  class CancelOrder < BaseService
    def initialize(order:)
      @order = order
    end

    def call
      raise Error, I18n.t("advertising.errors.order_not_cancellable") unless order.active?

      AdvertisingOrder.transaction do
        order.media_plans.active.find_each do |plan|
          Airtime::Cancel.call(plan: plan)
        end
        order.update!(status: :cancelled)
      end
      order
    end

    private

    attr_reader :order
  end
end
