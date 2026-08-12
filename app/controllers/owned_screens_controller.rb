# frozen_string_literal: true

class OwnedScreensController < ApplicationController
  before_action :require_user
  before_action :set_screen, only: %i[show edit update destroy]

  def index
    authorize Screen, policy_class: OwnedScreenPolicy
    @screens = policy_scope(Screen, policy_scope_class: OwnedScreenPolicy::Scope)
      .includes(station: :location)
      .order(:name)
  end

  def show
    authorize @screen, policy_class: OwnedScreenPolicy
  end

  def new
    @screen = Screen.new(orientation: :landscape)
    authorize @screen, policy_class: OwnedScreenPolicy
    load_form_collections
  end

  def create
    @screen = Screen.new(screen_params)
    @screen.owner_organization = Current.user.organization
    authorize @screen, policy_class: OwnedScreenPolicy

    if station_matches_location? && @screen.save
      redirect_to owned_screen_path(@screen), notice: t('.created')
    else
      load_form_collections
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @screen, policy_class: OwnedScreenPolicy
    load_form_collections
  end

  def update
    authorize @screen, policy_class: OwnedScreenPolicy
    @screen.assign_attributes(screen_params)
    if station_matches_location? && @screen.save
      redirect_to owned_screen_path(@screen), notice: t('.updated')
    else
      load_form_collections
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @screen, policy_class: OwnedScreenPolicy
    @screen.destroy!
    redirect_to owned_screens_path, notice: t('.destroyed')
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to owned_screen_path(@screen), alert: t('.destroy_restricted')
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t('media_assets.authentication_required')
  end

  def set_screen
    @screen = policy_scope(Screen, policy_scope_class: OwnedScreenPolicy::Scope).find(params[:id])
  end

  def screen_params
    params.require(:screen).permit(:name, :orientation, :station_id)
  end

  def load_form_collections
    @locations = Location.order(:name)
    @stations = Station.includes(:location).order(:name)
    @selected_location_id = params[:location_id].presence&.to_i
    @selected_location_id ||= @screen.station&.location_id if @screen&.station_id.present?
  end

  def station_matches_location?
    location_id = params[:location_id].presence&.to_i
    return true if location_id.blank?

    station = Station.find_by(id: @screen.station_id)
    if station.nil? || station.location_id != location_id
      @screen.errors.add(:station_id, :invalid)
      false
    else
      true
    end
  end
end
