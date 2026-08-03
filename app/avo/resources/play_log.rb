# frozen_string_literal: true

class Avo::Resources::PlayLog < Avo::Resources::ApplicationResource
  self.model_class = ::PlayLog

  def fields
    field :id, as: :id
    field :started_at, as: :date_time
    field :source, as: :text
    field :organization, as: :belongs_to
    field :screen, as: :belongs_to
    field :media_asset, as: :belongs_to
  end
end
