# frozen_string_literal: true

class Avo::Resources::Station < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :name, as: :text
    field :offline_cache_hours, as: :number
    field :agent_token_digest, as: :text
    field :location, as: :belongs_to
    field :screens, as: :has_many
  end
end
