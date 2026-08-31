# frozen_string_literal: true

require "administrate/base_dashboard"

module Directory
  class BusinessSphereDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      name: Field::String,
      profiles: Field::HasMany,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      name
      profiles
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      name
      profiles
      created_at
      updated_at
    ].freeze

    FORM_ATTRIBUTES = %i[
      name
    ].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(business_sphere)
      business_sphere.name
    end
  end
end
