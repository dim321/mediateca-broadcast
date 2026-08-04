# frozen_string_literal: true

class CreateFleetHierarchy < ActiveRecord::Migration[8.1]
  def change
    create_table :locations do |t|
      t.string :name, null: false

      t.timestamps
    end
    add_index :locations, :name, unique: true

    create_table :stations do |t|
      t.references :location, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :offline_cache_hours, null: false, default: 24
      t.string :agent_token_digest

      t.timestamps
    end
    add_index :stations, %i[location_id name], unique: true

    create_table :screens do |t|
      t.references :station, null: false, foreign_key: true
      t.string :name, null: false
      t.string :orientation, null: false, default: 'landscape'

      t.timestamps
    end
    add_index :screens, %i[station_id name], unique: true

    create_table :screen_tags do |t|
      t.references :screen, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
    add_index :screen_tags, %i[screen_id tag_id], unique: true
  end
end
