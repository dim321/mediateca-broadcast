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

  def manager?
    user&.manager?
  end

  def accountant?
    user&.accountant?
  end

  def administrator?
    user&.administrator?
  end

  # Client LK mutators (R15) + operator Avo path.
  def client_mutator?
    return false unless user
    return true if operator?

    manager? || administrator?
  end

  # Media / rotations / groups / plans / airtime (KTD11 — accountant excluded).
  def lk_content_access?
    return false unless user
    return true if operator?

    manager? || administrator?
  end

  def in_organization?
    user.present? && record.organization_id == user.organization_id
  end

  def operator_or_in_organization?
    operator? || in_organization?
  end

  def lk_content_show?
    lk_content_access? && operator_or_in_organization?
  end

  def lk_content_mutate?
    client_mutator? && operator_or_in_organization?
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

    def lk_content_access?
      return false unless user
      return true if operator?

      user.manager? || user.administrator?
    end

    # Operators see the full catalog; managers/admins stay within tenant;
    # accountants get nothing for LK content scopes (KTD11).
    def resolve_tenant_scope
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless lk_content_access?

      scope.where(organization_id: user.organization_id)
    end
  end
end
