# frozen_string_literal: true

class MediaPlanPolicy < ApplicationPolicy
  def index? = lk_content_access?

  def show? = lk_content_show?

  def create? = client_mutator?

  def update? = lk_content_mutate?

  def cancel? = lk_content_mutate?

  def reschedule? = lk_content_mutate?

  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
