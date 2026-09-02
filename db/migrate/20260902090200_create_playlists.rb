# frozen_string_literal: true

class CreatePlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :playlists do |t|
      t.references :station, null: false, foreign_key: { on_delete: :restrict }
      t.date :for_date, null: false
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "current"
      t.datetime :generated_at
      t.string :etag
      t.datetime :broadcast_day_starts_at
      t.string :fingerprint

      t.timestamps
    end
    add_index :playlists, %i[station_id for_date], unique: true,
      where: "status = 'current'",
      name: "index_playlists_unique_current_per_station_date"
    add_index :playlists, %i[station_id for_date],
      name: "index_playlists_on_station_id_and_for_date"

    create_table :playlist_items do |t|
      t.references :playlist, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.references :media_asset, null: false, foreign_key: { on_delete: :restrict }
      t.integer :offset_seconds, null: false
      t.integer :duration_seconds, null: false
      t.string :source_kind, null: false
      t.references :media_plan, null: true, foreign_key: { on_delete: :nullify }

      t.timestamps
    end
    add_index :playlist_items, %i[playlist_id position], unique: true,
      name: "index_playlist_items_on_playlist_and_position"
    add_check_constraint :playlist_items, "position > 0",
      name: "playlist_items_position_positive"
    add_check_constraint :playlist_items, "offset_seconds >= 0",
      name: "playlist_items_offset_seconds_non_negative"
    add_check_constraint :playlist_items, "duration_seconds > 0",
      name: "playlist_items_duration_seconds_positive"

    create_table :playlist_item_screens do |t|
      t.references :playlist_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :screen, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :playlist_item_screens, %i[playlist_item_id screen_id], unique: true,
      name: "index_playlist_item_screens_on_item_and_screen"
  end
end
