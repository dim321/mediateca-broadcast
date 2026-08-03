# frozen_string_literal: true

class Avo::Resources::Screen < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :name, as: :text
    field :orientation, as: :select, enum: ::Screen.orientations
    field :organization, as: :belongs_to
    field :station, as: :belongs_to
    field :tags, as: :has_many, through: :screen_tags
    field :screen_tags, as: :has_many
  end
end
