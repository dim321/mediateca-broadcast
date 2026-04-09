# frozen_string_literal: true

module Avo
  module Resources
    class MediaAsset < ApplicationResource
      self.includes = %i[organization uploaded_by]
      self.attachments = %i[file preview]

      def fields
        field :id, as: :id
        field :organization, as: :belongs_to
        field :uploaded_by, as: :belongs_to
        field :processing_status
        field :content_kind
        field :duration_seconds
        field :metadata, as: :code, language: "json", only_on: :show
        field :created_at
        field :updated_at
        field :file, as: :file, readonly: true
        field :preview, as: :file, readonly: true
      end
    end
  end
end
