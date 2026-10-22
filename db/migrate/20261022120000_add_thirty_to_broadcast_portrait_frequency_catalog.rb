# frozen_string_literal: true

class AddThirtyToBroadcastPortraitFrequencyCatalog < ActiveRecord::Migration[8.1]
  CONSTRAINT = "broadcast_portraits_block_frequencies_catalog"

  def up
    replace_catalog([ 1, 2, 3, 4, 5, 6, 10, 12, 20, 30 ])
  end

  def down
    replace_catalog([ 1, 2, 3, 4, 5, 6, 10, 12, 20 ])
  end

  private

  def replace_catalog(catalog)
    remove_check_constraint :broadcast_portraits, name: CONSTRAINT
    add_check_constraint :broadcast_portraits,
      "block_frequencies_per_hour <@ ARRAY[#{catalog.join(', ')}]::integer[]",
      name: CONSTRAINT
  end
end
