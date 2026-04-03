# frozen_string_literal: true

class PlaylistsController < ApplicationController
  before_action :require_user
  before_action :set_playlist, only: %i[show edit update destroy]

  def index
    authorize Playlist
    @playlists = policy_scope(Playlist).order(:name)
  end

  def show
    authorize @playlist
    @items = @playlist.ordered_items
    @available_media = policy_scope(MediaAsset).ready.with_attached_file.order(created_at: :desc).where.not(
      id: @playlist.media_asset_ids
    )
    @playlist_item = PlaylistItem.new(playlist: @playlist)
  end

  def new
    @playlist = Playlist.new(organization: Current.user.organization)
    authorize @playlist
  end

  def create
    @playlist = Playlist.new(playlist_params)
    @playlist.organization = Current.user.organization
    authorize @playlist
    if @playlist.save
      redirect_to @playlist, notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @playlist
  end

  def update
    authorize @playlist
    if @playlist.update(playlist_params)
      redirect_to @playlist, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @playlist
    @playlist.destroy!
    redirect_to playlists_path, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_playlist
    @playlist = policy_scope(Playlist).find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(:name)
  end
end
