# frozen_string_literal: true

class CreateBroadcastPointGroupsAndMediaPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :broadcast_point_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
    add_index :broadcast_point_groups, %i[organization_id name], unique: true

    create_table :broadcast_point_group_memberships do |t|
      t.references :broadcast_point_group, null: false, foreign_key: { on_delete: :cascade }
      t.references :screen, null: false, foreign_key: true

      t.timestamps
    end
    add_index :broadcast_point_group_memberships, %i[broadcast_point_group_id screen_id], unique: true,
      name: 'index_broadcast_point_group_memberships_unique'

    create_table :media_plans do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :rotation, null: false, foreign_key: { on_delete: :restrict }
      t.references :broadcast_point_group, null: false, foreign_key: { on_delete: :restrict }
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false

      t.timestamps
    end
    add_index :media_plans, %i[organization_id starts_at ends_at]
  end
end
