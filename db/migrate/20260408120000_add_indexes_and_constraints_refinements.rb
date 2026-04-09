# frozen_string_literal: true

class AddIndexesAndConstraintsRefinements < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :media_assets, %i[organization_id processing_status],
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_media_assets_on_organization_id_and_processing_status"

    add_index :media_assets, %i[organization_id created_at],
      order: { created_at: :desc },
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_media_assets_on_organization_id_and_created_at"

    add_index :schedule_rules, %i[organization_id playlist_id],
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_schedule_rules_on_organization_id_and_playlist_id"

    add_index :broadcast_points, %i[organization_id status],
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_broadcast_points_on_organization_id_and_status"
  end
end
