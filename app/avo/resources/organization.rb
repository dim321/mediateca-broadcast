# frozen_string_literal: true

class Avo::Resources::Organization < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :time_zone, as: :text
    field :kind, as: :select, enum: ::Organization.kinds
    field :users, as: :has_many
    field :media_assets, as: :has_many
    field :rotations, as: :has_many
    field :broadcast_point_groups, as: :has_many
    field :media_plans, as: :has_many
  end
end
