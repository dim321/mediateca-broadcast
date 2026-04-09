# frozen_string_literal: true

module Avo
  module Resources
    class BroadcastPoint < ApplicationResource
      self.includes = [ :organization ]

      def fields
        field :id, as: :id
        field :organization, as: :belongs_to
        field :name
        field :city
        field :venue_label
        field :time_zone
        field :status
        field :device_token_digest, only_on: :show
        field :created_at
        field :updated_at
        field :tags, as: :has_many
      end
    end
  end
end
