require "administrate/base_dashboard"

class MediaPlanDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    airtime_booking_id: Field::Number,
    broadcast_point_group: Field::BelongsTo,
    ends_at: Field::DateTime,
    organization: Field::BelongsTo,
    placement_kind: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    rotation: Field::BelongsTo,
    shows_per_hour: Field::Number,
    starts_at: Field::DateTime,
    status: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    organization
    broadcast_point_group
    placement_kind
    status
    starts_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    organization
    broadcast_point_group
    rotation
    placement_kind
    shows_per_hour
    starts_at
    ends_at
    status
    airtime_booking_id
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES — create/edit disabled; cancel/reschedule only.
  FORM_ATTRIBUTES = %i[].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how media plans are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(media_plan)
  #   "MediaPlan ##{media_plan.id}"
  # end
end
