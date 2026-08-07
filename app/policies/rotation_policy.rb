# frozen_string_literal: true

class RotationPolicy < ApplicationPolicy
  def index? = lk_content_access?

  def show? = lk_content_show?

  def create? = client_mutator?

  def update? = lk_content_mutate?

  def destroy? = lk_content_mutate?

  def reorder? = lk_content_mutate?

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
