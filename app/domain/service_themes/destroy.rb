# frozen_string_literal: true

module ServiceThemes
  class Destroy < BaseService
    def initialize(theme:)
      @theme = theme
    end

    def call
      ServiceTheme.transaction do
        rotations = theme.rotations
        theme.destroy!
        rotations.each(&:destroy!)
      end
    end

    private

    attr_reader :theme
  end
end
