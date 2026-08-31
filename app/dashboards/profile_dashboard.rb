# frozen_string_literal: true

require "administrate/base_dashboard"

class ProfileDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    organization: Field::BelongsTo,
    business_sphere: Field::BelongsTo.with_options(class_name: "Directory::BusinessSphere"),
    brand: Field::String,
    holding: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    organization
    business_sphere
    brand
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    organization
    business_sphere
    brand
    holding
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    business_sphere
    brand
    holding
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(profile)
    [ profile.brand, profile.holding, profile.business_sphere&.name ].compact_blank.first ||
      "Profile ##{profile.id}"
  end
end
