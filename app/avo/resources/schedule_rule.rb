# frozen_string_literal: true

module Avo
  module Resources
    class ScheduleRule < ApplicationResource
      self.includes = %i[organization playlist]

      def fields
        field :id, as: :id
        field :organization, as: :belongs_to
        field :playlist, as: :belongs_to
        field :starts_at
        field :ends_at
        field :timezone_context
        field :created_at
        field :updated_at
        field :schedule_targets, as: :has_many
        field :point_groups, as: :has_many
      end
    end
  end
end
