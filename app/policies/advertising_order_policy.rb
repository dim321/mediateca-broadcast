# frozen_string_literal: true

class AdvertisingOrderPolicy < ApplicationPolicy
  def index? = order_reader?

  def show? = order_reader? && operator_or_in_organization?

  def print? = show?

  def create? = client_mutator?

  def update? = client_mutator? && operator_or_in_organization? && record.draft?

  def activate? = traffic_manager? && operator_or_in_organization? && (record.draft? || record.active?)

  def reject? = traffic_manager? && operator_or_in_organization? && record.draft?

  def cancel? = client_mutator? && operator_or_in_organization? && record.active?

  def update_clips? = client_mutator? && operator_or_in_organization? && (record.draft? || record.active?)

  def replace_clip? = update_clips? && record.active?

  def destroy? = client_mutator? && operator_or_in_organization? && record.draft?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless user.manager? || user.administrator? || user.accountant? || user.traffic_manager?

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def order_reader?
    return false unless user
    return true if operator?

    manager? || administrator? || accountant? || traffic_manager?
  end
end
