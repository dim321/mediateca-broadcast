# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  private

  def operator?
    user&.organization&.operator?
  end

  def in_organization?
    user.present? && record.organization_id == user.organization_id
  end

  def operator_or_in_organization?
    operator? || in_organization?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.none
    end

    private

    attr_reader :user, :scope

    def operator?
      user&.organization&.operator?
    end

    # Operators see the full catalog; clients stay within their tenant.
    def resolve_tenant_scope
      return scope.none unless user
      return scope.all if operator?

      scope.where(organization_id: user.organization_id)
    end
  end
end
