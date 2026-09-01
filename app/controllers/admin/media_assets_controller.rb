# frozen_string_literal: true

module Admin
  class MediaAssetsController < Admin::BaseController
    def index
      @q = MediaAsset.ransack(ransack_params)
      @q.sorts = "created_at desc" if @q.sorts.empty?
      @media_assets = @q.result.includes(:organization).with_attached_file.page(params[:page]).per(25)
    end

    def show
      @media_asset = MediaAsset.with_attached_file.with_attached_preview.with_attached_broadcast_file.find(params[:id])
    end

    def edit
      @media_asset = MediaAsset.find(params[:id])
    end

    def update
      @media_asset = MediaAsset.find(params[:id])
      if @media_asset.update(media_asset_params)
        redirect_to admin_media_asset_path(@media_asset), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @media_asset = MediaAsset.find(params[:id])
      destroy_with_restriction(@media_asset, admin_media_assets_path, notice: t("admin.crud.destroyed"))
    end

    private

    def media_asset_params
      params.expect(
        media_asset: [
          :organization_id,
          :uploaded_by_id,
          :content_kind,
          :content_type,
          :visibility,
          :processing_status,
          :duration_seconds
        ]
      )
    end
  end
end
