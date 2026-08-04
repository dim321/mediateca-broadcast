# frozen_string_literal: true

class CreateMediaAndBroadcastCore < ActiveRecord::Migration[8.1]
  def change
    create_table :media_assets do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :processing_status, null: false, default: 'pending'
      t.string :content_kind, null: false
      t.integer :duration_seconds
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :media_assets, %i[organization_id processing_status]
    add_index :media_assets, %i[organization_id created_at], order: { created_at: :desc }

    create_table :rotations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
    add_index :rotations, %i[organization_id name], unique: true

    create_table :rotation_items do |t|
      t.references :rotation, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: { on_delete: :restrict }
      t.integer :position, null: false
      t.integer :display_duration_seconds

      t.timestamps
    end
    add_index :rotation_items, %i[rotation_id position], unique: true

    create_table :tags do |t|
      t.string :name, null: false

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_tags_on_lower_name ON tags (lower((name)::text));
        SQL
      end
      dir.down do
        execute 'DROP INDEX IF EXISTS index_tags_on_lower_name'
      end
    end
  end
end
