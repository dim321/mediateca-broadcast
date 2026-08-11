# frozen_string_literal: true

class RotationsController < ApplicationController
  before_action :require_user
  before_action :set_rotation, only: %i[show edit update destroy]

  def index
    authorize Rotation
    @rotations = policy_scope(Rotation).order(:name)
  end

  def show
    authorize @rotation
    @items = @rotation.ordered_items
    @available_media = policy_scope(MediaAsset).ready
      .with_attached_file
      .with_attached_broadcast_file
      .order(created_at: :desc)
      .where.not(id: @rotation.media_asset_ids)
    @rotation_item = RotationItem.new(rotation: @rotation)
  end

  def new
    @rotation = Rotation.new(organization: Current.user.organization)
    authorize @rotation
  end

  def create
    @rotation = Rotation.new(rotation_params)
    @rotation.organization = Current.user.organization
    authorize @rotation
    if @rotation.save
      redirect_to @rotation, notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @rotation
  end

  def update
    authorize @rotation
    if @rotation.update(rotation_params)
      redirect_to @rotation, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @rotation
    @rotation.destroy!
    redirect_to rotations_path, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_rotation
    @rotation = policy_scope(Rotation).find(params[:id])
  end

  def rotation_params
    params.require(:rotation).permit(:name)
  end
end
