# frozen_string_literal: true

class MoveBroadcastPortraitsToScreens < ActiveRecord::Migration[8.1]
  class Portrait < ApplicationRecord
    self.table_name = "broadcast_portraits"
    has_many :blocks, class_name: "MoveBroadcastPortraitsToScreens::Block",
      foreign_key: :broadcast_portrait_id, dependent: :destroy
  end

  class Block < ApplicationRecord
    self.table_name = "broadcast_portrait_blocks"
  end

  class ScreenRow < ApplicationRecord
    self.table_name = "screens"
  end

  def up
    add_reference :broadcast_portraits, :screen, null: true,
      foreign_key: { on_delete: :cascade }
    add_column :screens, :inherit_operating_hours_from_location, :boolean, null: false, default: true
    add_column :screens, :operating_hours, :jsonb, null: false, default: {}

    backfill_screen_portraits
    destroy_unassigned_station_portraits

    remove_index :broadcast_portraits, name: "index_broadcast_portraits_on_station_id_unique"
    remove_index :broadcast_portraits, name: "index_broadcast_portraits_one_default_template"
    remove_reference :broadcast_portraits, :station, foreign_key: { on_delete: :cascade }

    add_index :broadcast_portraits, :screen_id, unique: true,
      where: "screen_id IS NOT NULL",
      name: "index_broadcast_portraits_on_screen_id_unique"
    add_index :broadcast_portraits, :is_default, unique: true,
      where: "screen_id IS NULL AND is_default",
      name: "index_broadcast_portraits_one_default_template"
  end

  def down
    add_reference :broadcast_portraits, :station, null: true,
      foreign_key: { on_delete: :cascade }

    restore_station_portraits

    remove_index :broadcast_portraits, name: "index_broadcast_portraits_on_screen_id_unique"
    remove_index :broadcast_portraits, name: "index_broadcast_portraits_one_default_template"
    remove_reference :broadcast_portraits, :screen, foreign_key: { on_delete: :cascade }

    add_index :broadcast_portraits, :station_id, unique: true,
      where: "station_id IS NOT NULL",
      name: "index_broadcast_portraits_on_station_id_unique"
    add_index :broadcast_portraits, :is_default, unique: true,
      where: "station_id IS NULL AND is_default",
      name: "index_broadcast_portraits_one_default_template"

    remove_column :screens, :inherit_operating_hours_from_location
    remove_column :screens, :operating_hours
  end

  private

  def backfill_screen_portraits
    Portrait.reset_column_information
    station_portraits = Portrait.where.not(station_id: nil).includes(:blocks).to_a
    screens_by_station = ScreenRow.order(:id).group_by(&:station_id)

    station_portraits.each do |source|
      screens = screens_by_station[source.station_id] || []
      screens.each { |screen| copy_portrait(source, screen.id) }
      source.destroy!
    end
  end

  def destroy_unassigned_station_portraits
    Portrait.where.not(station_id: nil).where(screen_id: nil).find_each(&:destroy!)
  end

  def restore_station_portraits
    Portrait.reset_column_information
    Portrait.where.not(screen_id: nil).includes(:blocks).order(:id).group_by { |portrait|
      ScreenRow.find(portrait.screen_id).station_id
    }.each do |station_id, portraits|
      source = portraits.first
      source.update_column(:station_id, station_id)
      portraits.drop(1).each(&:destroy!)
    end
  end

  def copy_portrait(source, screen_id)
    copy = Portrait.create!(
      screen_id: screen_id,
      name: source.name,
      kind: source.kind,
      block_frequency_per_hour: source.block_frequency_per_hour,
      max_commercial_in_row: source.max_commercial_in_row,
      neutral_min_seconds: source.neutral_min_seconds,
      is_default: false
    )
    source.blocks.order(:position).each do |block|
      copy.blocks.create!(
        position: block.position,
        kind: block.kind,
        rotation_id: block.rotation_id,
        pick_strategy: block.pick_strategy,
        time_of_day: block.time_of_day
      )
    end
  end
end
