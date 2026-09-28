# frozen_string_literal: true

class MediaAssetPolicy < ApplicationPolicy
  def index? = media_library_access?

  def show?
    return false unless media_library_access?
    return true if operator?
    return true if in_organization?

    record.visibility_network?
  end

  def create? = client_mutator?

  def update? = lk_content_mutate?

  def destroy? = lk_content_mutate?

  def mark_content_validation?
    traffic_manager? && operator_or_in_organization?
  end

  def revoke_content_validation? = mark_content_validation?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if operator?
      return scope.none unless media_library_access?

      scope.where(organization_id: user.organization_id)
        .or(scope.where(visibility: MediaAsset.visibilities[:network]))
    end

    private

    def media_library_access?
      return false unless user
      return true if operator?

      user.manager? || user.administrator? || user.traffic_manager?
    end
  end

  private

  def media_library_access?
    return false unless user
    return true if operator?

    manager? || administrator? || traffic_manager?
  end
end
