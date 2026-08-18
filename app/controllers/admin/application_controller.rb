# frozen_string_literal: true

module Admin
  class ApplicationController < Administrate::ApplicationController
    include CurrentOrganization
    include LocaleSwitching

    helper ApplicationHelper

    before_action :authenticate_admin

    def authenticate_admin
      return if Current.user&.organization&.operator?

      redirect_to main_app.login_path, alert: I18n.t(
        "admin.authentication_required",
        default: "Operator sign-in required for admin."
      )
    end
  end
end
