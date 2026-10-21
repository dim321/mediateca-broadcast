# frozen_string_literal: true

module Fleet
  class ScreensForOrderPicker < BaseService
    def initialize(medium: nil)
      @medium = medium.presence
    end

    def call
      scope = Screen.operator_catalog
        .includes(:tags, :broadcast_portrait, :broadcast_point_groups, station: :location)
        .joins(station: :location)
      scope = scope.where(stations: { medium: @medium }) if @medium
      scope.order("locations.name", "stations.name", "screens.name")
    end
  end
end
