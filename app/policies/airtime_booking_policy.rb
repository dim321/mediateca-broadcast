# frozen_string_literal: true

class AirtimeBookingPolicy < ApplicationPolicy
  def index? = lk_content_access?

  def show? = lk_content_show?

  def create? = client_mutator?

  def new? = create?

  def cancel? = lk_content_mutate?

  def reschedule? = lk_content_mutate?

  class Scope < ApplicationPolicy::Scope
    def resolve = resolve_tenant_scope
  end
end
