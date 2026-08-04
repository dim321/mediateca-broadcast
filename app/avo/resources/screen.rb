# frozen_string_literal: true

class Avo::Resources::Screen < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :orientation, as: :select, enum: ::Screen.orientations
    field :station, as: :belongs_to
    field :tags, as: :has_many, through: :screen_tags
    field :screen_tags, as: :has_many
  end
end
