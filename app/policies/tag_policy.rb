# frozen_string_literal: true

class TagPolicy < ApplicationPolicy
  def index? = user.present?
  def show? = user.present?
  def create? = operator?
  def update? = operator?
  def destroy? = operator?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.all
    end
  end
end
