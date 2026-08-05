# frozen_string_literal: true

class Avo::Resources::AirtimeQuota < Avo::Resources::ApplicationResource
  self.model_class = ::AirtimeQuota
  self.includes = [ :broadcast_point_group ]

  def fields
    field :id, as: :id
    field :broadcast_point_group, as: :belongs_to
    field :starts_at, as: :date_time
    field :ends_at, as: :date_time
    field :seconds_total, as: :number
    field :seconds_remaining, as: :number
    field :content_type, as: :text
    field :airtime_bookings, as: :has_many
  end
end
