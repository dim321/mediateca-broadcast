# frozen_string_literal: true

module Fleet
  class FilterPoints < BaseService
    def initialize(scope:, tag_ids: nil)
      @scope = scope
      @tag_ids = Array(tag_ids).map(&:to_i).reject(&:zero?).uniq
    end

    def call
      return @scope if @tag_ids.empty?

      table = @scope.model.table_name
      subquery = @scope
        .reselect("#{table}.id")
        .joins(:tags)
        .where(tags: { id: @tag_ids })
        .group("#{table}.id")
        .having("COUNT(DISTINCT tags.id) = ?", @tag_ids.size)

      @scope.where(id: subquery)
    end
  end
end
