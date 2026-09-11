# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :require_user
  before_action :set_user

  def show
    authorize @user, policy_class: AccountPolicy
  end

  def update
    authorize @user, policy_class: AccountPolicy

    if @user.update(account_params)
      redirect_to account_path, notice: t(".updated"), status: :see_other
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def account_params
    attrs = params.expect(user: [
      :first_name, :last_name, :phone, :job_title, :telegram, :location, :avatar,
      :password, :password_confirmation
    ])
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    attrs
  end

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end
end
