# frozen_string_literal: true

class AddContentTypeAndVisibilityToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :media_assets, :content_type, :string, null: false, default: 'own'
    add_column :media_assets, :visibility, :string, null: false, default: 'organization'
    add_index :media_assets, :content_type
    add_index :media_assets, :visibility

    # Keep values on existing rows; force explicit choice for new LK uploads (R11/R12).
    change_column_default :media_assets, :content_type, from: 'own', to: nil
    change_column_default :media_assets, :visibility, from: 'organization', to: nil
  end
end
