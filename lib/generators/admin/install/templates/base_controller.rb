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

    def authenticate_admin
      return if Current.user&.organization&.operator?

      redirect_to main_app.login_path, alert: I18n.t(
        "admin.authentication_required",
        default: "Operator sign-in required for admin."
      )
    end
  end
end
