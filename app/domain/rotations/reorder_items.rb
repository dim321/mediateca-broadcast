# frozen_string_literal: true

module Rotations
  class ReorderItems < Rotations::BaseService
    def initialize(rotation:, ordered_ids:)
      @rotation = rotation
      @ordered_ids = ordered_ids.map(&:to_i)
    end

    def call
      RotationItem.transaction do
        items = @rotation.rotation_items.order(:id).lock.to_a
        validate_ids!(items)
        by_id = items.index_by(&:id)
        # Avoid unique (rotation_id, position) violations while swapping.
        base = [ @rotation.rotation_items.maximum(:position).to_i, items.size * 2 ].max + 1_000
        items.each_with_index { |it, i| it.update!(position: base + i) }
        @ordered_ids.each_with_index do |id, index|
          by_id[id].update!(position: index + 1)
        end
      end
    end

    private

    def validate_ids!(items)
      expected = items.map(&:id).sort
      got = @ordered_ids.sort
      raise ArgumentError, "rotation_item_ids must match current items" unless expected == got
    end
  end
end
