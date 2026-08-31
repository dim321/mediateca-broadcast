# frozen_string_literal: true

require "administrate/base_dashboard"

class AdvertisingOrderLineDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    advertising_order: Field::BelongsTo,
    broadcast_point_group: Field::BelongsTo,
    price_per_day_cents: Field::Number,
    total_shows: Field::Number,
    total_sum_cents: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    broadcast_point_group
    total_shows
    total_sum_cents
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    advertising_order
    broadcast_point_group
    price_per_day_cents
    total_shows
    total_sum_cents
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(line)
    line.broadcast_point_group&.name || "Line ##{line.id}"
  end
end
