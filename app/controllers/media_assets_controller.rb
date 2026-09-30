# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  before_action :require_user
  before_action :set_media_asset, only: %i[show update mark_content_validation revoke_content_validation]

  def index
    authorize MediaAsset
    load_media_assets
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

  def show
    authorize @media_asset
  end

  def update
    authorize @media_asset
    respond_to do |format|
      format.html { redirect_to media_assets_path }
      format.turbo_stream
    end
  end

  def mark_content_validation
    authorize @media_asset
    MediaAssets::MarkContentValidated.call(media_asset: @media_asset, user: Current.user)
    redirect_to media_asset_path(@media_asset), notice: t("media_assets.content_validation.marked"), status: :see_other
  rescue MediaAssets::Error => e
    redirect_to media_asset_path(@media_asset), alert: e.message, status: :see_other
  end

  def revoke_content_validation
    authorize @media_asset
    MediaAssets::RevokeContentValidation.call(media_asset: @media_asset)
    redirect_to media_asset_path(@media_asset), notice: t("media_assets.content_validation.revoked"), status: :see_other
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_media_asset
    @media_asset = policy_scope(MediaAsset).includes(:content_validated_by).find(params[:id])
  end

  def media_asset_params
    params.fetch(:media_asset, {}).permit(:file, :content_type, :visibility)
  end

  def media_asset_create_params
    permitted = media_asset_params.slice(:content_type, :visibility)
    permitted.delete(:content_type) unless MediaAsset.cabinet_content_types.include?(permitted[:content_type])
    permitted
  end

  def respond_created
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to media_assets_path, notice: t(".created") }
    end
  end

  def respond_create_failed
    load_media_assets
    flash.now[:alert] = t(".create_failed")
    render :index, status: :unprocessable_content
  end

  def load_media_assets
    @q = policy_scope(MediaAsset).ransack(ransack_params)
    @q.sorts = "created_at desc" if @q.sorts.empty?
    @media_assets = @q.result
      .with_attached_file
      .with_attached_preview
      .with_attached_broadcast_file
  end

  def ransack_params
    params[:q].is_a?(ActionController::Parameters) ? params[:q] : {}
  end
end
