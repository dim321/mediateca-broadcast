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
FactoryBot.define do
  factory :advertising_order_line do
    advertising_order
    screen { association :screen, owner_organization: advertising_order.organization }
    price_per_day_cents { 34_020_00 }

    trait :with_days do
      after(:create) do |line|
        create(
          :advertising_order_line_day,
          advertising_order_line: line,
          date: Date.new(2026, 6, 3),
          shows: 36
        )
      end
    end
  end
end
