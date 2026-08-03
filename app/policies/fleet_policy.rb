# frozen_string_literal: true

class FleetPolicy < ApplicationPolicy
  def index? = operator?

  def show? = in_operator_organization?

  def create? = operator?

  def update? = in_operator_organization?

  def destroy? = in_operator_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.organization&.operator?

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def in_operator_organization?
    operator? && record.organization_id == user.organization_id
  end
end
