# frozen_string_literal: true

module Rotations
  class RotationItemComponent < ViewComponent::Base
    def initialize(rotation:, item:)
      @rotation = rotation
      @item = item
    end

    attr_reader :rotation, :item
  end
end
