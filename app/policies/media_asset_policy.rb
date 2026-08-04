# frozen_string_literal: true

class MediaAssetPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = operator_or_in_organization?

  def create? = user.present?

  def update? = operator_or_in_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
