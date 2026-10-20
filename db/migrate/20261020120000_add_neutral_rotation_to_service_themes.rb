# frozen_string_literal: true

class AddNeutralRotationToServiceThemes < ActiveRecord::Migration[8.1]
  class MigrationRotation < ApplicationRecord
    self.table_name = "rotations"
  end

  class MigrationServiceTheme < ApplicationRecord
    self.table_name = "service_themes"
  end

  def up
    add_reference :service_themes, :neutral_rotation, foreign_key: { to_table: :rotations, on_delete: :restrict },
      null: true

    MigrationServiceTheme.reset_column_information
    MigrationServiceTheme.find_each do |theme|
      rotation = MigrationRotation.create!(
        organization_id: theme.organization_id,
        name: "#{theme.name} · neutral",
        system_managed: true
      )
      theme.update_columns(neutral_rotation_id: rotation.id)
    end

    change_column_null :service_themes, :neutral_rotation_id, false
  end

  def down
    remove_reference :service_themes, :neutral_rotation, foreign_key: true
  end
end
