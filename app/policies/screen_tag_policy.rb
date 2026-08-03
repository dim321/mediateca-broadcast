# frozen_string_literal: true

class ScreenTagPolicy < ApplicationPolicy
  def index? = operator?
  def show? = screen_in_operator_organization?
  def create? = operator?
  def update? = screen_in_operator_organization?
  def destroy? = screen_in_operator_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.organization&.operator?

      scope.joins(:screen).where(screens: { organization_id: user.organization_id })
    end
  end

  private

  def screen_in_operator_organization?
    operator? && record.screen.organization_id == user.organization_id
  end
end
