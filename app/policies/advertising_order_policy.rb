# frozen_string_literal: true

class AdvertisingOrderPolicy < ApplicationPolicy
  def index? = order_reader?

  def show? = order_reader? && operator_or_in_organization?

  def print? = show?

  def create? = client_mutator?

  def update? = client_mutator? && operator_or_in_organization? && record.draft?

  def activate? = client_mutator? && operator_or_in_organization? && (record.draft? || record.active?)

  def cancel? = client_mutator? && operator_or_in_organization? && !record.cancelled? && !record.completed?

  def destroy? = client_mutator? && operator_or_in_organization? && record.draft?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless user.manager? || user.administrator? || user.accountant?

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def order_reader?
    return false unless user
    return true if operator?

    manager? || administrator? || accountant?
  end
end
