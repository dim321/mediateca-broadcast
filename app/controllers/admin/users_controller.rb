# frozen_string_literal: true

module Admin
  class UsersController < Admin::BaseController
    def index
      @q = User.ransack(ransack_params)
      @q.sorts = "email asc" if @q.sorts.empty?
      @users = @q.result.includes(:organization).page(params[:page]).per(25)
    end

    def show
      @user = User.find(params[:id])
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      if @user.save
        redirect_to admin_user_path(@user), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @user = User.find(params[:id])
    end

    def update
      @user = User.find(params[:id])
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @user = User.find(params[:id])
      destroy_with_restriction(@user, admin_users_path, notice: t("admin.crud.destroyed"))
    end

    private

    def user_params
      attrs = params.expect(user: [ :email, :organization_id, :role, :password, :password_confirmation ])
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
      attrs
    end
  end
end
