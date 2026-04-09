class Avo::Resources::ScheduleRule < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :playlist_id, as: :number
    field :starts_at, as: :date_time
    field :ends_at, as: :date_time
    field :timezone_context, as: :select, enum: ::ScheduleRule.timezone_contexts
    field :organization, as: :belongs_to
    field :playlist, as: :belongs_to
    field :schedule_targets, as: :has_many
    field :point_groups, as: :has_many, through: :schedule_targets
  end
end
