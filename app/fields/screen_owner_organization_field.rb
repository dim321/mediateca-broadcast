# frozen_string_literal: true

require "administrate/field/belongs_to"

class ScreenOwnerOrganizationField < Administrate::Field::BelongsTo
  def selected_option
    super || Organization.operator.pick(:id)
  end

  def include_blank_option
    false
  end

  private

  def candidate_resources
    Organization.order(Arel.sql("CASE WHEN kind = 'operator' THEN 0 ELSE 1 END"), :name)
  end
end
