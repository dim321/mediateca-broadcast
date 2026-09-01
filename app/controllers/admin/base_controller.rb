# frozen_string_literal: true

module Admin
  class BaseController < ActionController::Base
    include CurrentOrganization
    include LocaleSwitching

    helper ApplicationHelper
    helper AdminHelper

    layout "admin/operator"

    before_action :authenticate_admin

    stale_when_importmap_changes

    private

    def ransack_params
      params[:q].is_a?(ActionController::Parameters) ? params[:q] : {}
    end

    def destroy_with_restriction(record, success_path, notice:, alert: nil)
      record.destroy!
      redirect_to success_path, notice: notice, status: :see_other
    rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
      redirect_to success_path, alert: alert || t("admin.crud.destroy_restricted"), status: :see_other
    end

    def authenticate_admin
      return if Current.user&.organization&.operator?

      redirect_to main_app.login_path, alert: I18n.t(
        "admin.authentication_required",
        default: "Operator sign-in required for admin."
      )
    end
  end
end
