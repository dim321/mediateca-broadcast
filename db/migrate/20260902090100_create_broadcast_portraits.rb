# frozen_string_literal: true

class CreateBroadcastPortraits < ActiveRecord::Migration[8.1]
  def change
    create_table :broadcast_portraits do |t|
      t.references :station, null: true, foreign_key: { on_delete: :cascade },
        index: { unique: true, where: "station_id IS NOT NULL", name: "index_broadcast_portraits_on_station_id_unique" }
      t.string :name, null: false
      t.string :kind, null: false, default: "cyclic"
      t.integer :block_frequency_per_hour, null: false
      t.integer :max_commercial_in_row, null: false, default: 3
      t.integer :neutral_min_seconds, null: false, default: 10
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end
    add_index :broadcast_portraits, :is_default, unique: true,
      where: "station_id IS NULL AND is_default",
      name: "index_broadcast_portraits_one_default_template"
    add_check_constraint :broadcast_portraits, "block_frequency_per_hour BETWEEN 1 AND 60",
      name: "broadcast_portraits_block_frequency_per_hour_range"
    add_check_constraint :broadcast_portraits, "max_commercial_in_row > 0",
      name: "broadcast_portraits_max_commercial_in_row_positive"
    add_check_constraint :broadcast_portraits, "neutral_min_seconds IN (5, 10)",
      name: "broadcast_portraits_neutral_min_seconds_allowed"

    create_table :broadcast_portrait_blocks do |t|
      t.references :broadcast_portrait, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.string :kind, null: false
      t.references :rotation, null: true, foreign_key: { on_delete: :restrict }
      t.string :pick_strategy
      t.time :time_of_day

      t.timestamps
    end
    add_index :broadcast_portrait_blocks, %i[broadcast_portrait_id position], unique: true,
      name: "index_broadcast_portrait_blocks_on_portrait_and_position"
    add_check_constraint :broadcast_portrait_blocks, "position > 0",
      name: "broadcast_portrait_blocks_position_positive"
  end
end
