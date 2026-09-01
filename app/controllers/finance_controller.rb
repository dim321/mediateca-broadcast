# frozen_string_literal: true

# Accountant stub (KTD11) — finance reports land in MVP-5.
class FinanceController < ApplicationController
  before_action :require_user

  def show
    unless Current.user.accountant? || Current.user.administrator? || Current.user.organization.operator?
      flash[:alert] = I18n.t("pundit.not_authorized")
      redirect_back(fallback_location: rails_health_check_path)
    end
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end
end
