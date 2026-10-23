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

    def destroy
      theme = ServiceTheme.find(params[:service_theme_id])
      item = RotationItem.find(params[:id])
      rotation = item.rotation
      ServiceThemes::RemoveClip.call(theme: theme, rotation_item: item)
      refresh_folder(theme, rotation, notice: t("admin.service_themes.clip_removed"), removed_item: item)
    rescue ArgumentError
      redirect_to admin_service_theme_path(theme), alert: t("admin.service_themes.clip_not_in_folder"),
        status: :see_other
    end

    def place
      theme = ServiceTheme.find(params[:service_theme_id])
      asset = MediaAsset.find(params[:media_asset_id])
      item = ServiceThemes::PlaceValidatedClip.call(theme: theme, role: params[:role], media_asset: asset)
      refresh_folder(theme, item.rotation, notice: t("admin.service_themes.clip_placed"), added_item: item)
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

    def refresh_folder(theme, rotation, notice:, added_item: nil, removed_item: nil)
      rotation.rotation_items.reset

      respond_to do |format|
        format.turbo_stream { render_folder_streams(theme, rotation, notice, added_item:, removed_item:) }
        format.html { redirect_to admin_service_theme_path(theme), notice: notice, status: :see_other }
      end
    end

    def render_folder_streams(theme, rotation, notice, added_item:, removed_item:)
      flash.now[:notice] = notice
      content_type = ServiceTheme.content_type_for_role(folder_role(theme, rotation))
      render turbo_stream: [
        folder_list_stream(theme, rotation, added_item:, removed_item:),
        turbo_stream.replace(
          helpers.dom_id(rotation, :place_select),
          partial: "admin/service_themes/place_select",
          locals: { rotation: rotation, content_type: content_type }
        ),
        turbo_stream.replace("flash", partial: "admin/shared/flash")
      ]
    end

    def folder_list_stream(theme, rotation, added_item:, removed_item:)
      if removed_item
        turbo_stream.remove(helpers.dom_id(removed_item))
      elsif added_item && rotation.rotation_items.one?
        turbo_stream.replace(
          helpers.dom_id(rotation, :clips),
          partial: "admin/service_themes/folder_clips",
          locals: { service_theme: theme, rotation: rotation, entering: added_item }
        )
      else
        turbo_stream.append(
          helpers.dom_id(rotation, :clip_rows),
          partial: "admin/service_themes/folder_clip_row",
          locals: { service_theme: theme, item: added_item, animate: true }
        )
      end
    end

    def folder_role(theme, rotation)
      ServiceTheme::FOLDER_ROLES.find { |role| theme.rotation_for(role).id == rotation.id }
    end
  end
end
