# frozen_string_literal: true

class BroadcastPointGroupPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = operator_or_in_organization?

  def create? = user.present?

  def update? = operator_or_in_organization?

  def add_screens? = operator_or_in_organization?

  def remove_member? = operator_or_in_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
