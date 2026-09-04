# frozen_string_literal: true

module Admin
  class ServiceThemesController < Admin::BaseController
    def index
      @q = ServiceTheme.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @service_themes = @q.result.page(params[:page]).per(25)
    end

    def show
      @service_theme = ServiceTheme.find(params[:id])
    end

    def new
      @service_theme = ServiceTheme.new
    end

    def create
      @service_theme = ServiceThemes::Create.call(
        organization: Current.user.organization,
        name: service_theme_params[:name]
      )
      redirect_to admin_service_theme_path(@service_theme), notice: t("admin.service_themes.created"),
        status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      @service_theme = e.record
      render :new, status: :unprocessable_content
    end

    def edit
      @service_theme = ServiceTheme.find(params[:id])
    end

    def update
      @service_theme = ServiceTheme.find(params[:id])
      if @service_theme.update(service_theme_params)
        redirect_to admin_service_theme_path(@service_theme), notice: t("admin.service_themes.updated"),
          status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @service_theme = ServiceTheme.find(params[:id])
      ServiceThemes::Destroy.call(theme: @service_theme)
      redirect_to admin_service_themes_path, notice: t("admin.service_themes.destroyed"), status: :see_other
    rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey
      redirect_to admin_service_themes_path, alert: t("admin.service_themes.destroy_restricted"), status: :see_other
    end

    private

    def service_theme_params
      permitted = params.expect(service_theme: [ :name ])
      permitted[:name] = permitted[:name].to_s.strip
      permitted
    end
  end
end
