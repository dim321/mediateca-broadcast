# frozen_string_literal: true

class BroadcastPointGroupPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = in_organization?

  def create? = user.present?

  def new? = create?

  def update? = in_organization?

  def edit? = update?

  def add_screens? = in_organization?

  def remove_member? = in_organization?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def in_organization?
    user.present? && record.organization_id == user.organization_id
  end
end
