# frozen_string_literal: true

class MakeAdvertisingOrdersMediaAssetIdNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :advertising_orders, :media_asset_id, true
  end
end
