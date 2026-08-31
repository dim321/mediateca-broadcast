# frozen_string_literal: true

require "administrate/base_dashboard"

class AdvertisingOrderDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    organization: Field::BelongsTo,
    created_by: Field::BelongsTo.with_options(class_name: "User"),
    media_asset: Field::BelongsTo,
    rotation: Field::BelongsTo,
    product_name: Field::String,
    business_sphere: Field::String,
    clip_title: Field::String,
    duration_seconds: Field::Number,
    placement_kind: LocalizedSelectField.with_options(searchable: false),
    status: LocalizedSelectField.with_options(searchable: false),
    coefficient_percent: Field::Number,
    discount_cents: Field::Number,
    total_shows: Field::Number,
    total_sum_cents: Field::Number,
    document_version: Field::Number,
    advertising_order_lines: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    organization
    product_name
    status
    created_by
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    organization
    created_by
    product_name
    business_sphere
    media_asset
    clip_title
    duration_seconds
    rotation
    placement_kind
    status
    coefficient_percent
    discount_cents
    total_shows
    total_sum_cents
    document_version
    advertising_order_lines
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(advertising_order)
    advertising_order.product_name.presence || "AdvertisingOrder ##{advertising_order.id}"
  end
end
