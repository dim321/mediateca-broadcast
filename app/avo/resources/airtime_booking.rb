# frozen_string_literal: true

class Avo::Resources::AirtimeBooking < Avo::Resources::ApplicationResource
  self.model_class = ::AirtimeBooking
  self.includes = [ :organization, :broadcast_point_group, :airtime_quota ]

  def fields
    field :id, as: :id
    field :organization, as: :belongs_to
    field :broadcast_point_group, as: :belongs_to
    field :airtime_quota, as: :belongs_to
    field :starts_at, as: :date_time
    field :ends_at, as: :date_time
    field :seconds, as: :number
    field :status, as: :select, enum: ::AirtimeBooking.statuses
  end
end
