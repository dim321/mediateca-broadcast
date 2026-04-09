class Avo::Resources::MediaAsset < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :organization_id, as: :number
    field :uploaded_by_id, as: :number
    field :processing_status, as: :select, enum: ::MediaAsset.processing_statuses
    field :content_kind, as: :select, enum: ::MediaAsset.content_kinds
    field :duration_seconds, as: :number
    field :metadata, as: :code
    field :file, as: :file
    field :preview, as: :file
    field :organization, as: :belongs_to
    field :uploaded_by, as: :belongs_to
    field :playlist_items, as: :has_many
    field :playlists, as: :has_many, through: :playlist_items
  end
end
