# frozen_string_literal: true

module Advertising
  class CompleteExpiredOrdersJob < ApplicationJob
    queue_as :default

    def perform
      AdvertisingOrder.active.includes(:organization, :advertising_order_line_days).find_each do |order|
        max_date = order.advertising_order_line_days.map(&:date).max
        next if max_date.blank?

        today = Time.current.in_time_zone(order.organization.time_zone).to_date
        order.completed! if max_date < today
      end
    end
  end
end
