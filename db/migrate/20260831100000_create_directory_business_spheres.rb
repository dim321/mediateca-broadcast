# frozen_string_literal: true

class CreateDirectoryBusinessSpheres < ActiveRecord::Migration[8.1]
  def change
    create_table :directory_business_spheres do |t|
      t.string :name, null: false

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_directory_business_spheres_on_lower_name
          ON directory_business_spheres (lower((name)::text));
        SQL
      end
      dir.down do
        execute "DROP INDEX IF EXISTS index_directory_business_spheres_on_lower_name"
      end
    end
  end
end
