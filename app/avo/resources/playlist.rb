# frozen_string_literal: true

module Avo
  module Resources
    class Playlist < ApplicationResource
      self.includes = [ :organization ]

      def fields
        field :id, as: :id
        field :organization, as: :belongs_to
        field :name
        field :created_at
        field :updated_at
        field :playlist_items, as: :has_many
        field :schedule_rules, as: :has_many
      end
    end
  end
end
