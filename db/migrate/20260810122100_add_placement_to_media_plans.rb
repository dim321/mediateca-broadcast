# frozen_string_literal: true

class AddPlacementToMediaPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :media_plans, :placement_kind, :string, null: false, default: "own_atmosphere"
    add_column :media_plans, :shows_per_hour, :integer
    add_index :media_plans, :placement_kind
  end
end
