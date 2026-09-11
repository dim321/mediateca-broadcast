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
    end

    def create
      @station = Station.new(station_params)
      if @station.save
        redirect_to admin_station_path(@station), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @station = Station.find(params[:id])
    end

    def update
      @station = Station.find(params[:id])
      if @station.update(station_params)
        redirect_to admin_station_path(@station), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
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

    def playlist_date_for(station)
      Date.iso8601(params[:date].to_s)
    rescue Date::Error, ArgumentError
      Time.current.in_time_zone(station.location.time_zone).to_date
    end
  end
end
