# frozen_string_literal: true

class AddScreenOwnerAndLocationOperatingHours < ActiveRecord::Migration[8.0]
  def change
    add_reference :screens, :owner_organization, foreign_key: { to_table: :organizations }, null: true
    add_column :locations, :operating_hours, :jsonb, null: false, default: {}
  end
end
