class Avo::Resources::Organization < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :name, as: :text
    field :time_zone, as: :text
    field :users, as: :has_many
    field :media_assets, as: :has_many
    field :playlists, as: :has_many
    field :broadcast_points, as: :has_many
    field :point_groups, as: :has_many
    field :schedule_rules, as: :has_many
  end
end
