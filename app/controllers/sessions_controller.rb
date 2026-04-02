# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :set_current_request_context, only: %i[new create]
  before_action :redirect_if_signed_in, only: :new

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to media_assets_path, notice: t(".signed_in")
    else
      flash.now[:alert] = t(".invalid_credentials")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: t(".signed_out")
  end

  private

  def redirect_if_signed_in
    redirect_to media_assets_path if session[:user_id].present?
  end
end
