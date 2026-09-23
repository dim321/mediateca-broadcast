# frozen_string_literal: true

class AdvertisingOrderMailer < ApplicationMailer
  def draft_created(order)
    @order = order
    @notice = I18n.t("advertising_orders.create.created", name: order.product_name)

    mail to: order.created_by.email, subject: @notice
  end
end
