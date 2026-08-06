require "administrate/base_dashboard"

class AirtimeQuotaDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    airtime_bookings: Field::HasMany,
    broadcast_point_group: Field::BelongsTo,
    content_type: Field::String,
    ends_at: Field::DateTime,
    seconds_remaining: Field::Number,
    seconds_total: Field::Number,
    starts_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    airtime_bookings
    broadcast_point_group
    content_type
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    airtime_bookings
    broadcast_point_group
    content_type
    ends_at
    seconds_remaining
    seconds_total
    starts_at
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    airtime_bookings
    broadcast_point_group
    content_type
    ends_at
    seconds_remaining
    seconds_total
    starts_at
  ].freeze

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

  # Overwrite this method to customize how airtime quotas are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(airtime_quota)
  #   "AirtimeQuota ##{airtime_quota.id}"
  # end
end
