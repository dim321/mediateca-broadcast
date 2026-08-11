# frozen_string_literal: true

class LocationsController < ApplicationController
  before_action :require_user
  before_action :set_location, only: %i[edit update]

  def index
    authorize Location
    @locations = policy_scope(Location).order(:name)
    return if operator_user?

    @locations = @locations
      .joins(stations: :screens)
      .where(screens: { owner_organization_id: Current.user.organization_id })
      .distinct
  end

  def edit
    authorize @location
  end

  def update
    authorize @location
    if @location.update(location_params)
      redirect_to locations_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def operator_user?
    Current.user&.organization&.operator?
  end

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_location
    @location = policy_scope(Location).find(params[:id])
  end

  def location_params
    params.require(:location).permit(
      operating_hours: Location::OperatingHours::DAY_KEYS.index_with { %i[start end] }
    )
  end
end
