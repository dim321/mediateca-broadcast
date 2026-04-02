# frozen_string_literal: true

module CurrentOrganization
  extend ActiveSupport::Concern

  included do
    before_action :set_current_request_context
  end

  private

  def set_current_request_context
    Current.user = User.find_by(id: session[:user_id]) if session[:user_id].present?
    Current.organization = Current.user&.organization
  end
end
