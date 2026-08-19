# frozen_string_literal: true

require "administrate/field/select"

class ScreenLocationField < Administrate::Field::Select
  def self.searchable?
    false
  end

  def selectable_options
    Location.order(:name).map { |location| [ location.name, location.id ] }
  end

  def include_blank_option
    I18n.t("helpers.label.screen.location_blank")
  end

  def html_controller
    nil
  end
end
