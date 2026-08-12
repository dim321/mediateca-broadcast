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
    organization: Field::BelongsTo,
    uploaded_by: Field::BelongsTo,
    content_kind: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    content_type: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    visibility: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    processing_status: Field::Select.with_options(searchable: false, collection: ->(field) { field.resource.class.send(field.attribute.to_s.pluralize).keys }),
    duration_seconds: Field::Number,
    metadata: Field::String.with_options(searchable: false),
    file: ActiveStorageAttachmentField,
    preview: ActiveStorageAttachmentField,
    broadcast_file: ActiveStorageAttachmentField,
    play_logs: Field::HasMany,
    rotation_items: Field::HasMany,
    rotations: Field::HasMany,
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
    content_kind
    content_type
    processing_status
    file
    created_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    organization
    uploaded_by
    content_kind
    content_type
    visibility
    processing_status
    duration_seconds
    metadata
    file
    preview
    broadcast_file
    play_logs
    rotation_items
    rotations
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    organization
    uploaded_by
    content_kind
    content_type
    visibility
    processing_status
    duration_seconds
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
  def display_resource(media_asset)
    "MediaAsset ##{media_asset.id}"
  end
end
