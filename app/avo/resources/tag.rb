# frozen_string_literal: true

class Avo::Resources::Tag < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :organization, as: :belongs_to
    field :screens, as: :has_many, through: :screen_tags
    field :broadcast_points, as: :has_many, through: :broadcast_point_tags
  end
end
