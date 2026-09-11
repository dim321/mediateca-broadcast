# frozen_string_literal: true

class MediaAssetPolicy < ApplicationPolicy
  def index? = lk_content_access?

  def show?
    return false unless lk_content_access?
    return true if operator?
    return true if in_organization?

    record.visibility_network?
  end

  def create? = client_mutator?

  def update? = lk_content_mutate?

  def destroy? = lk_content_mutate?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless lk_content_access?

      scope.where(organization_id: user.organization_id)
        .or(scope.where(visibility: MediaAsset.visibilities[:network]))
    end
  end
end
