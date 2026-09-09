# frozen_string_literal: true

# == Schema Information
#
# Table name: advertising_order_lines
#
#  id                   :bigint           not null, primary key
#  price_per_day_cents  :integer          not null
#  total_shows          :integer          default(0), not null
#  total_sum_cents      :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  advertising_order_id :bigint           not null
#  screen_id            :bigint           not null
#
# Indexes
#
#  index_advertising_order_lines_on_advertising_order_id  (advertising_order_id)
#  index_advertising_order_lines_on_order_and_screen      (advertising_order_id,screen_id) UNIQUE
#  index_advertising_order_lines_on_screen_id             (screen_id)
#
# Foreign Keys
#
#  fk_rails_...  (advertising_order_id => advertising_orders.id) ON DELETE => cascade
#  fk_rails_...  (screen_id => screens.id) ON DELETE => restrict
#
class AdvertisingOrderLine < ApplicationRecord
  belongs_to :advertising_order
  belongs_to :screen

  has_many :advertising_order_line_days, dependent: :destroy
  has_many :media_plans, dependent: :restrict_with_exception

  validates :price_per_day_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_shows, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_sum_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :screen_id, uniqueness: { scope: :advertising_order_id }
end
