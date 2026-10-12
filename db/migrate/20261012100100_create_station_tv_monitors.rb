# frozen_string_literal: true

class CreateStationTvMonitors < ActiveRecord::Migration[8.1]
  def change
    create_table :station_tv_monitors do |t|
      t.references :station, null: false, foreign_key: true, index: { unique: true }
      t.integer :health_interval_seconds, null: false, default: 30
      t.boolean :auto_restart_when_not_playing, null: false, default: true
      t.integer :telemetry_interval_seconds, null: false, default: 60

      t.timestamps
    end
  end
end
