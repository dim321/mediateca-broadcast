# frozen_string_literal: true

module Airtime
  # Transaction-scoped advisory locks on screen ids (KTD3).
  # Namespace key keeps airtime locks separate from other advisory users.
  class ScreenLock < BaseService
    NAMESPACE = 874_201

    def initialize(screen_ids:)
      @screen_ids = Array(screen_ids).compact.map(&:to_i).uniq.sort
    end

    def call
      screen_ids.each do |screen_id|
        ApplicationRecord.connection.execute(
          ApplicationRecord.sanitize_sql_array(
            [ "SELECT pg_advisory_xact_lock(?, ?)", NAMESPACE, screen_id ]
          )
        )
      end
      screen_ids
    end

    private

    attr_reader :screen_ids
  end
end
