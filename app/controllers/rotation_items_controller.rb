# frozen_string_literal: true

class RotationItemsController < ApplicationController
  before_action :require_user
  before_action :set_rotation

  def create
    @item = @rotation.rotation_items.build(rotation_item_params)
    authorize @rotation, :update?
    if @item.save
      redirect_to @rotation, notice: t(".created")
    else
      redirect_to @rotation, alert: @item.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @item = @rotation.rotation_items.find(params[:id])
    authorize @rotation, :update?
    @item.destroy!
    redirect_to @rotation, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_rotation
    @rotation = policy_scope(Rotation).find(params[:rotation_id])
  end

  def rotation_item_params
    params.require(:rotation_item).permit(:media_asset_id)
  end
end
