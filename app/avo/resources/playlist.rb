class Avo::Resources::Playlist < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :name, as: :text
    field :organization, as: :belongs_to
    field :playlist_items, as: :has_many
    field :media_assets, as: :has_many, through: :playlist_items
    field :schedule_rules, as: :has_many
  end
end
