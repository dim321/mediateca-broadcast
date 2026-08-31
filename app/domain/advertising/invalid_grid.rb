# frozen_string_literal: true

module Advertising
  class InvalidGrid < Error
    attr_reader :order

    def initialize(order)
      @order = order
      super("grid is invalid")
    end
  end
end
