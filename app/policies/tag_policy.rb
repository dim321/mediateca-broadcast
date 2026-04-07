# frozen_string_literal: true

class TagPolicy < ApplicationPolicy
  def index? = user.present?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.where(organization_id: user.organization_id)
    end
  end
end
