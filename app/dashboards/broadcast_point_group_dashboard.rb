require "administrate/base_dashboard"

class BroadcastPointGroupDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    broadcast_point_group_memberships: Field::HasMany,
    media_plans: Field::HasMany,
    name: Field::String,
    organization: Field::BelongsTo,
    screens: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    organization
    media_plans
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    broadcast_point_group_memberships
    media_plans
    name
    organization
    screens
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    organization
    screens
  ].freeze

  COLLECTION_FILTERS = {}.freeze
end
