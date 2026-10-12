# frozen_string_literal: true

class CreateTelemetrySnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :station_telemetry_snapshots do |t|
      t.references :station, null: false, foreign_key: true, index: { unique: true }
      t.datetime :reported_at, null: false
      t.integer :uptime_seconds, null: false
      t.string :package_etag, null: false, default: ""
      t.boolean :broadcast_ok, null: false, default: false
      t.jsonb :ignored_screen_ids, null: false, default: []

      t.timestamps
    end

    create_table :screen_telemetry_snapshots do |t|
      t.references :screen, null: false, foreign_key: true, index: { unique: true }
      t.references :station, null: false, foreign_key: true
      t.datetime :reported_at, null: false
      t.boolean :reachable, null: false, default: false
      t.boolean :agent_ok, null: false, default: false
      t.boolean :playing, null: false, default: false
      t.string :url, null: false, default: ""
      t.string :wakefulness, null: false, default: ""
      t.integer :stream_port, null: false, default: 0
      t.integer :broadcast_clients, null: false, default: 0
      t.string :last_error

      t.timestamps
    end
  end
end
