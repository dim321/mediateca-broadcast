# frozen_string_literal: true

module Admin
  class LocationsController < Admin::BaseController
    def index
      @q = Location.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @locations = @q.result.page(params[:page]).per(25)
    end

    def show
      @location = Location.includes(:stations).find(params[:id])
    end

    def new
      @location = Location.new
    end

    def create
      @location = Location.new(location_params)
      if @location.save
        redirect_to admin_location_path(@location), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @location = Location.find(params[:id])
    end

    def update
      @location = Location.find(params[:id])
      if @location.update(location_params)
        redirect_to admin_location_path(@location), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @location = Location.find(params[:id])
      destroy_with_restriction(@location, admin_locations_path, notice: t("admin.crud.destroyed"))
    end

    private

    def location_params
      hours = Location::OperatingHours::DAY_KEYS.index_with { [ :start, :end ] }
      params.require(:location).permit(:name, operating_hours: hours)
    end
  end
end
