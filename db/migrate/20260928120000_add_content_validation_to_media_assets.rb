# frozen_string_literal: true

class AddContentValidationToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :media_assets, :content_validated_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :media_assets, :content_validated_at, :datetime
  end
end
