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
      @agent_commands = @screen.agent_commands.order(issued_at: :desc).limit(20)
    end

    def new
      station = station_for_screen_guard
      if audio_station_screen_full?(station)
        redirect_to admin_station_path(station), alert: audio_station_full_message, status: :see_other
        return
      end

      @screen = Screen.new(
        inherit_operating_hours_from_location: true,
        template_id: default_template_id,
        station_id: station&.id,
        location_id: station&.location_id
      )
    end

    def create
      station = Station.find_by(id: screen_params[:station_id])
      if audio_station_screen_full?(station)
        redirect_to admin_station_path(station), alert: audio_station_full_message, status: :see_other
        return
      end

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
      station = Station.find_by(id: screen_params[:station_id])
      if audio_station_screen_full?(station, except_screen: @screen)
        @screen.assign_attributes(screen_params)
        @screen.errors.add(:station_id, :audio_station_full)
        assign_service_theme_fields(@screen)
        render :edit, status: :unprocessable_content
        return
      end

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
        :neutral_pick_strategy,
        :inherit_operating_hours_from_location,
        tag_ids: [],
        operating_hours: hours
      )
    end

    def default_template_id
      BroadcastPortrait.templates.find_by(is_default: true)&.id
    end

    def station_for_screen_guard
      station_id = params[:station_id].presence || params.dig(:screen, :station_id)
      Station.find_by(id: station_id) if station_id.present?
    end

    def audio_station_screen_full?(station, except_screen: nil)
      return false unless station&.audio?

      scope = station.screens
      scope = scope.where.not(id: except_screen.id) if except_screen
      scope.exists?
    end

    def audio_station_full_message
      I18n.t("activerecord.errors.models.screen.attributes.station_id.audio_station_full")
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

      filler = portrait.blocks.detect(&:filler?)
      screen.neutral_pick_strategy = filler.pick_strategy if filler&.pick_strategy.present?
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
