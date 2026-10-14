# frozen_string_literal: true

module Admin
  class StationScreenRefreshesController < Admin::BaseController
    def create
      station = Station.find(params[:station_id])
      result = Agent::Commands::FetchScreens.call(station:)
      key = result.created? ? "queued" : "already_queued"

      redirect_to admin_station_path(station),
        notice: t("admin.stations.screen_refresh.#{key}"),
        status: :see_other
    end
  end
end
