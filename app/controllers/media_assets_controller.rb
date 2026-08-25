# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  before_action :require_user
  before_action :set_media_asset, only: :update

  def index
    authorize MediaAsset
    @media_assets = policy_scope(MediaAsset)
      .with_attached_file
      .with_attached_preview
      .with_attached_broadcast_file
      .order(created_at: :desc)
    @media_asset = MediaAsset.new
  end

  def create
    @media_asset = MediaAsset.new(media_asset_create_params)
    @media_asset.organization = Current.user.organization
    @media_asset.uploaded_by = Current.user
    @media_asset.file.attach(media_asset_params[:file]) if media_asset_params[:file].present?

    authorize @media_asset

    if @media_asset.save
      respond_created
    else
      respond_create_failed
    end
  rescue StandardError => e
    raise unless @media_asset&.persisted? && Media::StorageErrors.network?(e)

    ProcessMediaMetadataJob.perform_later(@media_asset.id)
    respond_created
  end

  def update
    authorize @media_asset
    respond_to do |format|
      format.html { redirect_to media_assets_path }
      format.turbo_stream
    end
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_media_asset
    @media_asset = policy_scope(MediaAsset).find(params[:id])
  end

  def media_asset_params
    params.fetch(:media_asset, {}).permit(:file, :content_type, :visibility)
  end

  def media_asset_create_params
    media_asset_params.slice(:content_type, :visibility)
  end

  def respond_created
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to media_assets_path, notice: t(".created") }
    end
  end

  def respond_create_failed
    @media_assets = policy_scope(MediaAsset)
      .with_attached_file
      .with_attached_preview
      .with_attached_broadcast_file
      .order(created_at: :desc)
    flash.now[:alert] = t(".create_failed")
    render :index, status: :unprocessable_entity
  end
end
