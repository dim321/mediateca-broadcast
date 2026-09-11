# frozen_string_literal: true

class OwnedScreenPolicy < ApplicationPolicy
  def index?
    return false unless user
    return false if operator?

    lk_content_access?
  end

  def show?
    return false unless index?

    record.owner_organization_id == user.organization_id
  end

  def update? = show? && client_mutator?

  def destroy? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.none if operator?
      return scope.none unless lk_content_access?

      scope.where(owner_organization_id: user.organization_id)
    end
  end
end
