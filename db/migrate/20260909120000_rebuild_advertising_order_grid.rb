# frozen_string_literal: true

class RebuildAdvertisingOrderGrid < ActiveRecord::Migration[8.1]
  def up
    wipe_advertising_orders!

    add_column :advertising_orders, :shows_per_hour, :integer

    create_table :advertising_order_windows do |t|
      t.references :advertising_order, null: false, foreign_key: { on_delete: :cascade }
      t.time :starts_at, null: false
      t.time :ends_at, null: false

      t.timestamps
    end
    add_check_constraint :advertising_order_windows, "starts_at < ends_at",
      name: "advertising_order_windows_ends_after_starts"

    add_reference :advertising_order_lines, :screen, null: false, foreign_key: { on_delete: :restrict }

    remove_index :advertising_order_lines, name: "index_advertising_order_lines_on_order_and_group"
    remove_reference :advertising_order_lines, :broadcast_point_group, foreign_key: true

    add_index :advertising_order_lines, %i[advertising_order_id screen_id], unique: true,
      name: "index_advertising_order_lines_on_order_and_screen"

    create_table :media_plan_screens do |t|
      t.references :media_plan, null: false, foreign_key: { on_delete: :cascade }
      t.references :screen, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :media_plan_screens, %i[media_plan_id screen_id], unique: true,
      name: "index_media_plan_screens_on_plan_and_screen"

    change_column_null :media_plans, :broadcast_point_group_id, true
    change_column_null :airtime_bookings, :broadcast_point_group_id, true
  end

  def down
    change_column_null :airtime_bookings, :broadcast_point_group_id, false
    change_column_null :media_plans, :broadcast_point_group_id, false

    drop_table :media_plan_screens

    remove_index :advertising_order_lines, name: "index_advertising_order_lines_on_order_and_screen"
    add_reference :advertising_order_lines, :broadcast_point_group, null: false,
      foreign_key: { on_delete: :restrict }
    add_index :advertising_order_lines, %i[advertising_order_id broadcast_point_group_id], unique: true,
      name: "index_advertising_order_lines_on_order_and_group"
    remove_reference :advertising_order_lines, :screen, foreign_key: true

    drop_table :advertising_order_windows
    remove_column :advertising_orders, :shows_per_hour
  end

  private

  def wipe_advertising_orders!
    execute <<~SQL.squish
      UPDATE media_plans
      SET advertising_order_line_id = NULL
      WHERE advertising_order_line_id IS NOT NULL
    SQL

    execute "DELETE FROM advertising_order_line_days"
    execute "DELETE FROM advertising_order_lines"
    execute "DELETE FROM advertising_orders"
  end
end
