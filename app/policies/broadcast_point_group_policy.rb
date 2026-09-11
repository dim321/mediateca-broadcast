# frozen_string_literal: true

class BroadcastPointGroupPolicy < ApplicationPolicy
  def index? = lk_content_access?

  def show? = lk_content_show?

  def create? = client_mutator?

  def update? = lk_content_mutate?

  def add_screens? = lk_content_mutate?

  def remove_member? = lk_content_mutate?

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
