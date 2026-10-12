# frozen_string_literal: true

class CreateAgentCommands < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_commands do |t|
      t.references :station, null: false, foreign_key: true
      t.references :screen, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :command_type, null: false
      t.jsonb :params, null: false, default: {}
      t.datetime :issued_at, null: false
      t.string :status, null: false, default: "pending"
      t.boolean :succeeded
      t.string :result_error
      t.datetime :finished_at

      t.timestamps
    end

    add_index :agent_commands, :public_id, unique: true
    add_index :agent_commands, [ :station_id, :status ]
  end
end
