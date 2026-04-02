class ApplicationController < ActionController::Base
  include CurrentOrganization
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def current_user
    Current.user
  end

  def pundit_user
    Current.user
  end

  def user_not_authorized
    flash[:alert] = I18n.t("pundit.not_authorized", default: "You are not authorized to perform this action.")
    redirect_back(fallback_location: rails_health_check_path)
  end
end
