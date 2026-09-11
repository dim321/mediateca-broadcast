# frozen_string_literal: true

class FleetPolicy < ApplicationPolicy
  # Clients get read-only fleet catalog (R13); mutate stays operator-only.
  def index? = fleet_readable?

  def show? = fleet_readable?

  def create? = operator?

  def update? = operator?

  def destroy? = operator?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator? || lk_content_access?

      scope.none
    end
  end

  private

  def fleet_readable?
    return false unless user

    operator? || lk_content_access?
  end
end
