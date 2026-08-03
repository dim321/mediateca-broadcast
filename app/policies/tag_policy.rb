# frozen_string_literal: true

class TagPolicy < ApplicationPolicy
  def index? = user.present?
  def show? = in_organization?
  def create? = operator?
  def update? = in_operator_organization?
  def destroy? = in_operator_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def in_organization?
    user.present? && record.organization_id == user.organization_id
  end

  def in_operator_organization?
    operator? && record.organization_id == user.organization_id
  end
end
