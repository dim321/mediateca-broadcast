# frozen_string_literal: true

require "administrate/field/belongs_to"

class LocationScopedStationField < Administrate::Field::BelongsTo
  def associated_resource_options
    Station.includes(:location, :screens).joins(:location).order("locations.name", "stations.name").map do |station|
      [
        "#{station.location.name} · #{station.name}",
        station.id,
        {
          "data-location-id" => station.location_id,
          "data-suggested-name" => station.next_screen_name
        }
      ]
    end
  end

  def include_blank_option
    I18n.t("helpers.label.screen.station_blank")
  end

  def html_controller
    nil
  end
end
