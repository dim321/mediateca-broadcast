# frozen_string_literal: true

class PlaylistItemsController < ApplicationController
  before_action :require_user
  before_action :set_playlist

  def create
    @item = @playlist.playlist_items.build(playlist_item_params)
    authorize @playlist, :update?
    if @item.save
      redirect_to @playlist, notice: t(".created")
    else
      redirect_to @playlist, alert: @item.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @item = @playlist.playlist_items.find(params[:id])
    authorize @playlist, :update?
    @item.destroy!
    redirect_to @playlist, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_playlist
    @playlist = policy_scope(Playlist).find(params[:playlist_id])
  end

  def playlist_item_params
    params.require(:playlist_item).permit(:media_asset_id)
  end
end
