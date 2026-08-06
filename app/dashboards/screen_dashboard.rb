require "administrate/base_dashboard"

class ScreenDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    broadcast_point_group_memberships: Field::HasMany,
    broadcast_point_groups: Field::HasMany,
    name: Field::String,
    orientation: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    play_logs: Field::HasMany,
    screen_tags: Field::HasMany,
    station: Field::BelongsTo,
    tags: Field::HasMany,
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
    broadcast_point_group_memberships
    broadcast_point_groups
    name
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    broadcast_point_group_memberships
    broadcast_point_groups
    name
    orientation
    play_logs
    screen_tags
    station
    tags
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    broadcast_point_group_memberships
    broadcast_point_groups
    name
    orientation
    play_logs
    screen_tags
    station
    tags
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

  # Overwrite this method to customize how screens are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(screen)
  #   "Screen ##{screen.id}"
  # end
end
