# frozen_string_literal: true

module Admin
  class StationsController < Admin::BaseController
    def index
      @q = Station.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @stations = @q.result.includes(:location).page(params[:page]).per(25)
    end

    def show
      @station = Station.includes(:location, screens: :broadcast_portrait).find(params[:id])
      @playlist_date = playlist_date_for(@station)
      @playlist = @station.playlists.current.includes(items: [ :media_asset, :screens ]).find_by(for_date: @playlist_date)
    end

    def regenerate_playlists
      @station = Station.find(params[:id])
      Playlists::EnqueueRegen.from_station(@station)
      redirect_to admin_station_path(@station), notice: t("admin.stations.regen_enqueued"), status: :see_other
    end

    def new
      @station = Station.new
      @configure_tv_monitor = false
      @station.build_tv_monitor
    end

    def create
      @station = Station.new(station_params)
      monitor = drafted_monitor(@station)
      if save_station(@station, monitor)
        redirect_to admin_station_path(@station), notice: t("admin.crud.created"), status: :see_other
      else
        render_station_form(:new, monitor)
      end
    end

    def edit
      @station = Station.find(params[:id])
      @configure_tv_monitor = @station.tv_monitor.present?
      @station.build_tv_monitor unless @station.tv_monitor
    end

    def update
      @station = Station.find(params[:id])
      @station.assign_attributes(station_params)
      monitor = drafted_monitor(@station)
      if save_station(@station, monitor)
        redirect_to admin_station_path(@station), notice: t("admin.crud.updated"), status: :see_other
      else
        render_station_form(:edit, monitor)
      end
    end

    def destroy
      @station = Station.find(params[:id])
      destroy_with_restriction(@station, admin_stations_path, notice: t("admin.crud.destroyed"))
    end

    private

    def station_params
      params.expect(station: [ :location_id, :name, :offline_cache_hours ])
    end

    def configure_tv_monitor?
      ActiveModel::Type::Boolean.new.cast(params.dig(:station, :configure_tv_monitor))
    end

    def tv_monitor_input
      raw = params.dig(:station, :tv_monitor)
      return {} unless raw.respond_to?(:permit)

      raw.permit(:health_interval_seconds, :auto_restart_when_not_playing, :telemetry_interval_seconds)
    end

    def drafted_monitor(station)
      return unless configure_tv_monitor?

      monitor = station.tv_monitor || station.build_tv_monitor
      monitor.assign_attributes(tv_monitor_input)
      monitor
    end

    def save_station(station, monitor)
      station_ok = station.valid?
      monitor_ok = monitor.nil? || monitor.valid?
      return false unless station_ok && monitor_ok

      Station.transaction do
        station.save!
        if monitor
          monitor.station = station
          monitor.save!
        else
          station.tv_monitor&.destroy!
        end
      end
      true
    end

    def render_station_form(template, monitor)
      @configure_tv_monitor = configure_tv_monitor?
      if monitor
        @station.association(:tv_monitor).target = monitor
      else
        @station.build_tv_monitor unless @station.tv_monitor
      end
      render template, status: :unprocessable_content
    end

    def playlist_date_for(station)
      Date.iso8601(params[:date].to_s)
    rescue Date::Error, ArgumentError
      Time.current.in_time_zone(station.location.time_zone).to_date
    end
  end
end
