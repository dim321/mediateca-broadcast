# frozen_string_literal: true

module Admin
  class ProfilesController < Admin::BaseController
    def show
      @profile = Profile.includes(:organization, :business_sphere).find(params[:id])
    end
  end
end
