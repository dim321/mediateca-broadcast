# frozen_string_literal: true

module Admin
  class ScreensController < Admin::BaseController
    def index
      @q = Screen.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @screens = @q.result.includes(:station, :owner_organization).page(params[:page]).per(25)
    end

    def show
      @screen = Screen.includes(:tags, :station, :owner_organization, :broadcast_point_groups).find(params[:id])
    end

    def new
      @screen = Screen.new
    end

    def create
      @screen = Screen.new(screen_params)
      if @screen.save
        redirect_to admin_screen_path(@screen), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @screen = Screen.find(params[:id])
    end

    def update
      @screen = Screen.find(params[:id])
      if @screen.update(screen_params)
        redirect_to admin_screen_path(@screen), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @screen = Screen.find(params[:id])
      destroy_with_restriction(@screen, admin_screens_path, notice: t("admin.crud.destroyed"))
    end

    private

    def screen_params
      params.require(:screen).permit(
        :location_id,
        :station_id,
        :name,
        :orientation,
        :owner_organization_id,
        tag_ids: []
      )
    end
  end
end
