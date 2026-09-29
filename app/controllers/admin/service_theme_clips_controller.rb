# frozen_string_literal: true

module Admin
  class ServiceThemeClipsController < Admin::BaseController
    def create
      theme = ServiceTheme.find(params[:service_theme_id])
      asset = ServiceThemes::AddClip.call(
        theme: theme,
        role: params[:role],
        file: clip_file,
        uploaded_by: Current.user
      )
      redirect_to admin_media_asset_path(asset), notice: t("admin.service_themes.clip_uploaded"),
        status: :see_other
    rescue ArgumentError
      redirect_to admin_service_theme_path(theme), alert: t("admin.service_themes.unknown_role"),
        status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_service_theme_path(theme), alert: e.record.errors.full_messages.to_sentence,
        status: :see_other
    end

    def place
      theme = ServiceTheme.find(params[:service_theme_id])
      asset = MediaAsset.find(params[:media_asset_id])
      ServiceThemes::PlaceValidatedClip.call(theme: theme, role: params[:role], media_asset: asset)
      redirect_to admin_service_theme_path(theme), notice: t("admin.service_themes.clip_placed"),
        status: :see_other
    rescue ArgumentError
      redirect_to admin_service_theme_path(theme), alert: t("admin.service_themes.unknown_role"),
        status: :see_other
    rescue MediaAssets::Error, ActiveRecord::RecordInvalid => e
      message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
      redirect_to admin_service_theme_path(theme), alert: message, status: :see_other
    end

    private

    def clip_file
      params.dig(:clip, :file)
    end
  end
end
