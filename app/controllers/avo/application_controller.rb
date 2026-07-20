# frozen_string_literal: true

module Avo
  class ApplicationController < Avo::BaseApplicationController
    include CurrentOrganization

    # Avo needs Current set before its own auth/authorization callbacks.
    skip_before_action :set_current_request_context
    prepend_before_action :set_current_request_context

    def current_user
      ::Current.user
    end
  end
end
