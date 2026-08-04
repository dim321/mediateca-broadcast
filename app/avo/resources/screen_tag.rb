# frozen_string_literal: true

class Avo::Resources::ScreenTag < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :screen, as: :belongs_to
    field :tag, as: :belongs_to
  end
end
