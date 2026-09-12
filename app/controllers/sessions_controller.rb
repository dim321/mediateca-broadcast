# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :set_current_request_context, only: %i[new create]
  before_action :redirect_if_signed_in, only: :new

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      if user.blocked?
        flash.now[:alert] = t(".account_blocked")
        render :new, status: :unprocessable_content
      else
        session[:user_id] = user.id
        redirect_to after_authentication_path(user), notice: t(".signed_in")
      end
    else
      flash.now[:alert] = t(".invalid_credentials")
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: t(".signed_out")
  end

  private

  def redirect_if_signed_in
    return if session[:user_id].blank?

    user = User.find_by(id: session[:user_id])
    redirect_to after_authentication_path(user) if user&.active?
  end

  def after_authentication_path(user)
    user.organization.operator? ? admin_root_path : media_assets_path
  end
end
