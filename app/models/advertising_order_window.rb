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
class AdvertisingOrderWindow < ApplicationRecord
  belongs_to :advertising_order

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, :must_be_after_starts) unless ends_at > starts_at
  end
end
