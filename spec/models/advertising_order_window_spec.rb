# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe AdvertisingOrderWindow do
  it "belongs to an order and requires start before end on the same clock day" do
    order = create(:advertising_order)
    window = described_class.new(
      advertising_order: order,
      starts_at: "09:00",
      ends_at: "12:00"
    )
    expect(window).to be_valid

    window.ends_at = "08:00"
    expect(window).not_to be_valid
    expect(window.errors[:ends_at]).to be_present
  end
end
