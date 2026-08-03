# frozen_string_literal: true

class Avo::Resources::Station < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :name, as: :text
    field :offline_cache_hours, as: :number
    field :agent_token_digest, as: :text
    field :organization, as: :belongs_to
    field :location, as: :belongs_to
    field :screens, as: :has_many
  end
end
