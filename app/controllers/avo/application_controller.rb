# frozen_string_literal: true

module Avo
  class ApplicationController < Avo::BaseApplicationController
    prepend_before_action :sync_current_for_avo_context

    def current_user
      ::Current.user
    end

    private

    def sync_current_for_avo_context
      ::Current.user = ::User.find_by(id: session[:user_id]) if session[:user_id].present?
      ::Current.organization = ::Current.user&.organization
    end
  end
end
