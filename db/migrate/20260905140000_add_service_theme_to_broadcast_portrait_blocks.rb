# frozen_string_literal: true

class AddServiceThemeToBroadcastPortraitBlocks < ActiveRecord::Migration[8.1]
  def up
    add_reference :broadcast_portrait_blocks, :service_theme, null: true,
      foreign_key: { on_delete: :restrict }

    execute <<~SQL
      UPDATE broadcast_portrait_blocks AS blocks
      SET service_theme_id = themes.id
      FROM service_themes AS themes
      WHERE blocks.service_theme_id IS NULL
        AND (
          (blocks.kind = 'service_header_start' AND blocks.rotation_id = themes.header_start_rotation_id)
          OR (blocks.kind = 'service_header_end' AND blocks.rotation_id = themes.header_end_rotation_id)
          OR (blocks.kind = 'service_welcome' AND blocks.rotation_id = themes.welcome_rotation_id)
          OR (blocks.kind = 'service_close' AND blocks.rotation_id = themes.close_rotation_id)
        )
    SQL
  end

  def down
    remove_reference :broadcast_portrait_blocks, :service_theme, foreign_key: true
  end
end
