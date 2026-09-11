# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe AdvertisingOrderLineDay, type: :model do
  describe "validations" do
    it "requires a positive shows count" do
      day = build(:advertising_order_line_day, shows: 0)
      expect(day).not_to be_valid
      expect(day.errors[:shows]).to be_present
    end

    it "enforces uniqueness of a date within a line" do
      existing = create(:advertising_order_line_day, date: Date.new(2026, 6, 3), shows: 36)
      duplicate = build(
        :advertising_order_line_day,
        advertising_order_line: existing.advertising_order_line,
        date: existing.date,
        shows: 12
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:date]).to be_present
    end
  end

  describe "database constraints" do
    it "rejects non-positive shows at the database" do
      line = create(:advertising_order_line)
      expect {
        described_class.insert!(
          {
            advertising_order_line_id: line.id,
            date: Date.new(2026, 6, 3),
            shows: 0,
            created_at: Time.current,
            updated_at: Time.current
          }
        )
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
