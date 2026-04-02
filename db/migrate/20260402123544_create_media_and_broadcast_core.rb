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

    create_table :playlists do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :playlists, %i[organization_id name], unique: true

    create_table :playlist_items do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: { on_delete: :restrict }
      t.integer :position, null: false
      t.integer :display_duration_seconds

      t.timestamps
    end

    add_index :playlist_items, %i[playlist_id position], unique: true

    create_table :tags do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_tags_on_organization_and_lower_name
          ON tags (organization_id, lower(name));
        SQL
      end
      dir.down do
        execute 'DROP INDEX IF EXISTS index_tags_on_organization_and_lower_name'
      end
    end

    create_table :broadcast_points do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :city
      t.string :venue_label
      t.string :time_zone
      t.string :status, null: false, default: 'unknown'
      t.string :device_token_digest

      t.timestamps
    end

    create_table :broadcast_point_tags do |t|
      t.references :broadcast_point, null: false, foreign_key: true, index: false
      t.references :tag, null: false, foreign_key: true, index: false

      t.timestamps
    end

    add_index :broadcast_point_tags, :broadcast_point_id
    add_index :broadcast_point_tags, :tag_id
    add_index :broadcast_point_tags, %i[broadcast_point_id tag_id], unique: true

    create_table :point_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :point_groups, %i[organization_id name], unique: true

    create_table :point_group_memberships do |t|
      t.references :point_group, null: false, foreign_key: true
      t.references :broadcast_point, null: false, foreign_key: true

      t.timestamps
    end

    add_index :point_group_memberships, %i[point_group_id broadcast_point_id], unique: true,
      name: 'index_point_group_memberships_unique'

    create_table :schedule_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :playlist, null: false, foreign_key: { on_delete: :restrict }
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :timezone_context, null: false, default: 'organization'

      t.timestamps
    end

    add_index :schedule_rules, %i[organization_id starts_at ends_at]

    create_table :schedule_targets do |t|
      t.references :schedule_rule, null: false, foreign_key: { on_delete: :cascade }
      t.references :point_group, null: false, foreign_key: true

      t.timestamps
    end

    add_index :schedule_targets, %i[schedule_rule_id point_group_id], unique: true,
      name: 'index_schedule_targets_unique'
  end
end
