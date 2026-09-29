# frozen_string_literal: true

class AddRejectionReasonToAdvertisingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :advertising_orders, :rejection_reason, :string
  end
end
