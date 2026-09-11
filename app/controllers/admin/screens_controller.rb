# frozen_string_literal: true

module Admin
  class ScreensController < Admin::BaseController
    def index
      @q = Screen.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @screens = @q.result.includes(:station, :owner_organization).page(params[:page]).per(25)
    end

    def show
      @screen = Screen.includes(:tags, :station, :owner_organization, :broadcast_point_groups,
        broadcast_portrait: :service_theme).find(params[:id])
    end

    def new
      @screen = Screen.new(
        inherit_operating_hours_from_location: true,
        template_id: default_template_id
      )
    end

    def create
      @screen = Screen.new(screen_params)
      if @screen.save
        Portraits::CopyTemplate.call(screen: @screen, template: @screen.assigned_template)
        apply_service_theme!
        redirect_to admin_screen_path(@screen), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @screen = Screen.find(params[:id])
      assign_service_theme_fields(@screen)
    end

    def update
      @screen = Screen.find(params[:id])
      if @screen.update(screen_params)
        if @screen.template_id.present?
          Portraits::CopyTemplate.call(screen: @screen, template: @screen.assigned_template, replace: true)
        elsif hours_changed?
          Playlists::EnqueueRegen.from_screen(@screen)
        end
        apply_service_theme!
        redirect_to admin_screen_path(@screen), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @screen = Screen.find(params[:id])
      destroy_with_restriction(@screen, admin_screens_path, notice: t("admin.crud.destroyed"))
    end

    private

    def screen_params
      hours = Location::OperatingHours::DAY_KEYS.index_with { [ :start, :end ] }
      params.require(:screen).permit(
        :location_id,
        :station_id,
        :name,
        :orientation,
        :owner_organization_id,
        :template_id,
        :service_theme_id,
        :header_start_pick_strategy,
        :header_end_pick_strategy,
        :welcome_pick_strategy,
        :close_pick_strategy,
        :inherit_operating_hours_from_location,
        tag_ids: [],
        operating_hours: hours
      )
    end

    def default_template_id
      BroadcastPortrait.templates.find_by(is_default: true)&.id
    end

    def hours_changed?
      @screen.saved_change_to_inherit_operating_hours_from_location? ||
        (!@screen.inherit_operating_hours_from_location? && @screen.saved_change_to_operating_hours?)
    end

    def assign_service_theme_fields(screen)
      portrait = screen.broadcast_portrait
      return if portrait.blank?

      screen.service_theme_id = portrait.service_theme_id
      ServiceTheme::ROTATION_ROLES.each do |role, kind|
        strategy = portrait.blocks.detect { |block| block.kind == kind }&.pick_strategy
        screen.public_send(:"#{role}_pick_strategy=", strategy) if strategy.present?
      end
    end

    def apply_service_theme!
      return unless params[:screen].is_a?(ActionController::Parameters) && params[:screen].key?(:service_theme_id)

      theme = @screen.assigned_service_theme
      strategies = @screen.service_pick_strategies
      portrait = @screen.reload.broadcast_portrait
      return if portrait.blank?
      return if theme.nil? && portrait.service_theme_id.nil?

      Portraits::ApplyServiceTheme.call(
        portrait: portrait,
        theme: theme,
        pick_strategies: strategies
      )
    end
  end
end
