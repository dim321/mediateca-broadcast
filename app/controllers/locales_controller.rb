# frozen_string_literal: true

class LocalesController < ApplicationController
  def update
    locale = params[:locale].to_s.to_sym
    session[:locale] = locale if I18n.available_locales.include?(locale)
    redirect_back fallback_location: root_path
  end
end
