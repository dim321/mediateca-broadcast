# frozen_string_literal: true

class AddMediumToServiceThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :service_themes, :medium, :string, null: false, default: "video"
    add_check_constraint :service_themes, "medium IN ('video', 'audio')", name: "service_themes_medium_video_or_audio"
  end
end
