# frozen_string_literal: true

class CreatePlayLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :play_logs do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :screen, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.string :source, null: false, default: 'agent'

      t.timestamps
    end

    add_index :play_logs, %i[organization_id started_at]
    add_index :play_logs, %i[screen_id started_at]
  end
end
