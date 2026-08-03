# frozen_string_literal: true

class RenamePlaylistsToRotations < ActiveRecord::Migration[8.1]
  def up
    rename_table :playlists, :rotations
    rename_table :playlist_items, :rotation_items
    rename_column :rotation_items, :playlist_id, :rotation_id
    rename_column :schedule_rules, :playlist_id, :rotation_id
  end

  def down
    rename_column :schedule_rules, :rotation_id, :playlist_id
    rename_column :rotation_items, :rotation_id, :playlist_id
    rename_table :rotation_items, :playlist_items
    rename_table :rotations, :playlists
  end
end
