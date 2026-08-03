# frozen_string_literal: true

class Avo::Resources::Location < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :name, as: :text
    field :organization, as: :belongs_to
    field :stations, as: :has_many
  end
end
