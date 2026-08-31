# frozen_string_literal: true

module Fleet
  # Returns screens that have ALL of the given tags (AND semantics).
  class FilterScreens < BaseService
    def initialize(scope: Screen.all, tag_ids: [])
      @scope = scope
      @tag_ids = Array(tag_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      return @scope if @tag_ids.empty?

      @tag_ids.reduce(@scope) do |relation, tag_id|
        relation.where(id: ScreenTag.select(:screen_id).where(tag_id: tag_id))
      end
    end
  end
end
