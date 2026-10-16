# frozen_string_literal: true

class CreateStationStreamChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :station_stream_channels do |t|
      t.references :station, null: false, foreign_key: { on_delete: :cascade }
      t.string :timeline_digest, null: false, limit: 64
      t.integer :stream_port, null: false

      t.timestamps
    end

    add_index :station_stream_channels, [ :station_id, :timeline_digest ], unique: true
    add_index :station_stream_channels, [ :station_id, :stream_port ], unique: true
    add_check_constraint :station_stream_channels,
      "stream_port BETWEEN 8091 AND 8190",
      name: "station_stream_channels_stream_port_in_pool"
  end
end
