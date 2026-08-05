# frozen_string_literal: true

class AirtimeQuotaPolicy < ApplicationPolicy
  def index? = lk_content_access? || operator?

  def show?
    return false unless user
    return true if operator?
    return false unless lk_content_access?

    record.broadcast_point_group.organization_id == user.organization_id
  end

  def create? = operator?
  def update? = operator?
  def destroy? = operator?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless lk_content_access?

      scope.joins(:broadcast_point_group)
        .where(broadcast_point_groups: { organization_id: user.organization_id })
    end
  end
end
