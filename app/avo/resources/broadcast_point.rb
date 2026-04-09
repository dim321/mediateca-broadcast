class Avo::Resources::BroadcastPoint < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :name, as: :text
    field :city, as: :text
    field :venue_label, as: :text
    field :time_zone, as: :text
    field :status, as: :select, enum: ::BroadcastPoint.statuses
    field :device_token_digest, as: :text
    field :organization, as: :belongs_to
    field :point_group_memberships, as: :has_many
    field :point_groups, as: :has_many, through: :point_group_memberships
  end
end
