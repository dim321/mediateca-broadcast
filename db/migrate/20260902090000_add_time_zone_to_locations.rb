# frozen_string_literal: true

class AddTimeZoneToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :time_zone, :string, null: false, default: "UTC"
  end
end
