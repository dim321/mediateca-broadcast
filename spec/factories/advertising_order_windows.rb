# frozen_string_literal: true

# == Schema Information
#
# Table name: advertising_order_windows
#
#  id                   :bigint           not null, primary key
#  ends_at              :time             not null
#  starts_at            :time             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  advertising_order_id :bigint           not null
#
# Indexes
#
#  index_advertising_order_windows_on_advertising_order_id  (advertising_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (advertising_order_id => advertising_orders.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :advertising_order_window do
    advertising_order
    starts_at { "09:00" }
    ends_at { "12:00" }
  end
end
