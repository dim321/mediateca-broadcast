# frozen_string_literal: true

module Fleet
  class ScreensForOrderPicker < BaseService
    def call
      Screen.operator_catalog
        .includes(:tags, :broadcast_portrait, :broadcast_point_groups, station: :location)
        .joins(station: :location)
        .order("locations.name", "stations.name", "screens.name")
    end
  end
end
