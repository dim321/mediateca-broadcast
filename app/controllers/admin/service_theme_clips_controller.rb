# frozen_string_literal: true

module Admin
  class ServiceThemeClipsController < Admin::BaseController
    def create
      theme = ServiceTheme.find(params[:service_theme_id])
      ServiceThemes::AddClip.call(
        theme: theme,
        role: params[:role],
        file: clip_file,
        uploaded_by: Current.user
      )
      redirect_to admin_service_theme_path(theme), notice: t("admin.service_themes.clip_uploaded"),
        status: :see_other
    rescue ArgumentError
      redirect_to admin_service_theme_path(theme), alert: t("admin.service_themes.unknown_role"),
        status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_service_theme_path(theme), alert: e.record.errors.full_messages.to_sentence,
        status: :see_other
    end

    private

    def clip_file
      params.dig(:clip, :file)
    end
  end
end
