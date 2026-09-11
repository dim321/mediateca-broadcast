# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe AdvertisingOrderLine, type: :model do
  describe "validations" do
    it "rejects a negative price per day" do
      line = build(:advertising_order_line, price_per_day_cents: -1)
      expect(line).not_to be_valid
      expect(line.errors[:price_per_day_cents]).to be_present
    end

    it "rejects a second line for the same screen on the same order" do
      line = create(:advertising_order_line)
      duplicate = build(:advertising_order_line, advertising_order: line.advertising_order, screen: line.screen)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:screen_id]).to be_present
    end
  end

  describe "grid helper" do
    it "fills a date range with shows" do
      line = create(:advertising_order_line)
      dates = Date.new(2026, 6, 3)..Date.new(2026, 6, 5)

      create_order_line_days!(line, dates: dates, shows: 36)

      expect(line.advertising_order_line_days.count).to eq(3)
      expect(line.advertising_order_line_days.map(&:shows).uniq).to eq([ 36 ])
    end
  end
end
