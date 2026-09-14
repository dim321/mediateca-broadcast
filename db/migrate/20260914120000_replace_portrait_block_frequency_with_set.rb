# frozen_string_literal: true

class ReplacePortraitBlockFrequencyWithSet < ActiveRecord::Migration[8.1]
  CATALOG = [ 1, 2, 3, 4, 5, 6, 10, 12, 20 ].freeze

  def up
    add_column :broadcast_portraits, :block_frequencies_per_hour, :integer, array: true

    catalog_sql = CATALOG.join(',')
    execute <<~SQL
      UPDATE broadcast_portraits
      SET block_frequencies_per_hour = ARRAY[mapped.n]::integer[]
      FROM (
        SELECT id,
          CASE
            WHEN block_frequency_per_hour = ANY(ARRAY[#{catalog_sql}]) THEN block_frequency_per_hour
            ELSE COALESCE(
              (SELECT MAX(v) FROM unnest(ARRAY[#{catalog_sql}]) AS v
               WHERE v <= block_frequency_per_hour),
              1
            )
          END AS n
        FROM broadcast_portraits
      ) mapped
      WHERE broadcast_portraits.id = mapped.id
    SQL

    change_column_null :broadcast_portraits, :block_frequencies_per_hour, false
    add_check_constraint :broadcast_portraits,
      'cardinality(block_frequencies_per_hour) >= 1',
      name: 'broadcast_portraits_block_frequencies_present'
    add_check_constraint :broadcast_portraits,
      "block_frequencies_per_hour <@ ARRAY[#{catalog_sql}]::integer[]",
      name: 'broadcast_portraits_block_frequencies_catalog'
    remove_check_constraint :broadcast_portraits, name: 'broadcast_portraits_block_frequency_per_hour_range'
    remove_column :broadcast_portraits, :block_frequency_per_hour
  end

  def down
    add_column :broadcast_portraits, :block_frequency_per_hour, :integer
    execute <<~SQL
      UPDATE broadcast_portraits
      SET block_frequency_per_hour = block_frequencies_per_hour[1]
    SQL
    change_column_null :broadcast_portraits, :block_frequency_per_hour, false
    add_check_constraint :broadcast_portraits,
      'block_frequency_per_hour >= 1 AND block_frequency_per_hour <= 60',
      name: 'broadcast_portraits_block_frequency_per_hour_range'
    remove_check_constraint :broadcast_portraits, name: 'broadcast_portraits_block_frequencies_present'
    remove_check_constraint :broadcast_portraits, name: 'broadcast_portraits_block_frequencies_catalog'
    remove_column :broadcast_portraits, :block_frequencies_per_hour
  end
end
