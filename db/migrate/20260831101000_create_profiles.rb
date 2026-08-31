# frozen_string_literal: true

class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :business_sphere, null: true,
        foreign_key: { to_table: :directory_business_spheres, on_delete: :restrict }
      t.string :brand
      t.string :holding

      t.timestamps
    end
  end
end
