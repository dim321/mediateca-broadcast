# frozen_string_literal: true

class AddDistributionStrategyToAdvertisingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :advertising_orders, :distribution_strategy, :string,
      default: "linear", null: false
  end
end
