# frozen_string_literal: true

# == Schema Information
#
# Table name: advertising_order_line_days
#
#  id                        :bigint           not null, primary key
#  date                      :date             not null
#  shows                     :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  advertising_order_line_id :bigint           not null
#
# Indexes
#
#  index_advertising_order_line_days_on_advertising_order_line_id  (advertising_order_line_id)
#  index_advertising_order_line_days_on_line_and_date              (advertising_order_line_id,date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (advertising_order_line_id => advertising_order_lines.id) ON DELETE => cascade
#
class AdvertisingOrderLineDay < ApplicationRecord
  belongs_to :advertising_order_line

  validates :date, presence: true
  validates :date, uniqueness: { scope: :advertising_order_line_id }
  validates :shows, numericality: { only_integer: true, greater_than: 0 }
end
