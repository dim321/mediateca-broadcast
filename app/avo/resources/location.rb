# frozen_string_literal: true

class Avo::Resources::Location < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :stations, as: :has_many
  end
end
