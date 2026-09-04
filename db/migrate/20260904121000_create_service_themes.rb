# frozen_string_literal: true

class CreateServiceThemes < ActiveRecord::Migration[8.1]
  def change
    create_table :service_themes do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :restrict }
      t.string :name, null: false
      t.references :header_start_rotation, null: false,
        foreign_key: { to_table: :rotations, on_delete: :restrict }
      t.references :header_end_rotation, null: false,
        foreign_key: { to_table: :rotations, on_delete: :restrict }
      t.references :welcome_rotation, null: false,
        foreign_key: { to_table: :rotations, on_delete: :restrict }
      t.references :close_rotation, null: false,
        foreign_key: { to_table: :rotations, on_delete: :restrict }

      t.timestamps
    end

    add_index :service_themes, %i[organization_id name], unique: true,
      name: "index_service_themes_on_organization_id_and_name"

    add_reference :broadcast_portraits, :service_theme, null: true,
      foreign_key: { on_delete: :restrict }
  end
end
