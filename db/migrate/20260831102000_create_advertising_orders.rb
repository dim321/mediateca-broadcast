# frozen_string_literal: true

class CreateAdvertisingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :rotations, :system_managed, :boolean, null: false, default: false

    create_table :advertising_orders do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :restrict }
      t.references :created_by_user, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :business_sphere
      t.references :media_asset, null: false, foreign_key: { on_delete: :restrict }
      t.references :rotation, null: false, foreign_key: { on_delete: :restrict }, index: { unique: true }
      t.string :product_name, null: false
      t.string :clip_title
      t.integer :duration_seconds
      t.string :placement_kind, null: false, default: "own_atmosphere"
      t.string :status, null: false, default: "draft"
      t.integer :coefficient_percent, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :total_shows, null: false, default: 0
      t.integer :total_sum_cents, null: false, default: 0
      t.integer :document_version, null: false, default: 1

      t.timestamps
    end
    add_index :advertising_orders, :status
    add_check_constraint :advertising_orders, "discount_cents >= 0",
      name: "advertising_orders_discount_cents_non_negative"
    add_check_constraint :advertising_orders, "total_sum_cents >= 0",
      name: "advertising_orders_total_sum_cents_non_negative"
    add_check_constraint :advertising_orders, "total_shows >= 0",
      name: "advertising_orders_total_shows_non_negative"

    create_table :advertising_order_lines do |t|
      t.references :advertising_order, null: false, foreign_key: { on_delete: :cascade }
      t.references :broadcast_point_group, null: false, foreign_key: { on_delete: :restrict }
      t.integer :price_per_day_cents, null: false
      t.integer :total_shows, null: false, default: 0
      t.integer :total_sum_cents, null: false, default: 0

      t.timestamps
    end
    add_index :advertising_order_lines, %i[advertising_order_id broadcast_point_group_id], unique: true,
      name: "index_advertising_order_lines_on_order_and_group"
    add_check_constraint :advertising_order_lines, "price_per_day_cents >= 0",
      name: "advertising_order_lines_price_per_day_cents_non_negative"
    add_check_constraint :advertising_order_lines, "total_sum_cents >= 0",
      name: "advertising_order_lines_total_sum_cents_non_negative"
    add_check_constraint :advertising_order_lines, "total_shows >= 0",
      name: "advertising_order_lines_total_shows_non_negative"

    create_table :advertising_order_line_days do |t|
      t.references :advertising_order_line, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.integer :shows, null: false

      t.timestamps
    end
    add_index :advertising_order_line_days, %i[advertising_order_line_id date], unique: true,
      name: "index_advertising_order_line_days_on_line_and_date"
    add_check_constraint :advertising_order_line_days, "shows > 0",
      name: "advertising_order_line_days_shows_positive"

    add_reference :media_plans, :advertising_order_line, null: true,
      foreign_key: { on_delete: :restrict }
  end
end
