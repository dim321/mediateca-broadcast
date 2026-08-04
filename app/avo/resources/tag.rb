# frozen_string_literal: true

class Avo::Resources::Tag < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :screens, as: :has_many, through: :screen_tags
  end
end
