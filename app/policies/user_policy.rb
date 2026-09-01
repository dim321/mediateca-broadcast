# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index? = operator?
  def show? = operator?
  def create? = operator?
  def update? = operator?
  def destroy? = operator?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless operator?

      scope.all
    end
  end
end
