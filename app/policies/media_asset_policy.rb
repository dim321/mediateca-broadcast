# frozen_string_literal: true

class MediaAssetPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = in_organization?

  def create? = user.present?

  def update? = in_organization?

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
