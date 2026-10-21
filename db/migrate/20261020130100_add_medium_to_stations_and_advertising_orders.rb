# frozen_string_literal: true

class AddMediumToStationsAndAdvertisingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :stations, :medium, :string, null: false, default: "video"
    add_check_constraint :stations, "medium IN ('video', 'audio')", name: "stations_medium_video_or_audio"

    add_column :advertising_orders, :medium, :string, null: false, default: "video"
    add_check_constraint :advertising_orders,
      "medium IN ('video', 'audio')",
      name: "advertising_orders_medium_video_or_audio"
  end
end
