# frozen_string_literal: true

class AddAddressToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :address, :string, null: false, default: ""
    change_column_default :locations, :address, from: "", to: nil
  end
end
