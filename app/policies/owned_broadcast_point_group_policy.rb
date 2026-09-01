# frozen_string_literal: true

class OwnedBroadcastPointGroupPolicy < ApplicationPolicy
  def index?
    return false unless user
    return false if operator?

    lk_content_access?
  end

  def show?
    return false unless index?

    record.organization_id == user.organization_id
  end

  def update? = show? && client_mutator?

  def add_screens? = update?

  def remove_member? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.none if operator?
      return scope.none unless lk_content_access?

      scope.where(organization_id: user.organization_id)
    end
  end
end
