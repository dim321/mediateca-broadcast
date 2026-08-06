require "administrate/base_dashboard"

class MediaAssetDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    broadcast_file_attachment: Field::HasOne,
    broadcast_file_blob: Field::HasOne,
    content_kind: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    content_type: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    duration_seconds: Field::Number,
    file_attachment: Field::HasOne,
    file_blob: Field::HasOne,
    metadata: Field::String.with_options(searchable: false),
    organization: Field::BelongsTo,
    play_logs: Field::HasMany,
    preview_attachment: Field::HasOne,
    preview_blob: Field::HasOne,
    processing_status: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    rotation_items: Field::HasMany,
    rotations: Field::HasMany,
    uploaded_by: Field::BelongsTo,
    visibility: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
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
    broadcast_file_attachment
    broadcast_file_blob
    content_kind
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    broadcast_file_attachment
    broadcast_file_blob
    content_kind
    content_type
    duration_seconds
    file_attachment
    file_blob
    metadata
    organization
    play_logs
    preview_attachment
    preview_blob
    processing_status
    rotation_items
    rotations
    uploaded_by
    visibility
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    broadcast_file_attachment
    broadcast_file_blob
    content_kind
    content_type
    duration_seconds
    file_attachment
    file_blob
    metadata
    organization
    play_logs
    preview_attachment
    preview_blob
    processing_status
    rotation_items
    rotations
    uploaded_by
    visibility
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

  # Overwrite this method to customize how media assets are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(media_asset)
  #   "MediaAsset ##{media_asset.id}"
  # end
end
