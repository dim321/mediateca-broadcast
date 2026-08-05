# frozen_string_literal: true

class Avo::Resources::BroadcastPointGroup < Avo::Resources::ApplicationResource
  self.includes = [ :organization ]

  def fields
    field :id, as: :id
    field :name, as: :text
    field :organization, as: :belongs_to
    field :airtime_quotas, as: :has_many
    field :airtime_bookings, as: :has_many
  end
end
