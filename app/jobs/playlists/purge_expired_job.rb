# frozen_string_literal: true

module Playlists
  class PurgeExpiredJob < ApplicationJob
    queue_as :default

    def perform
      cutoff = Time.current.to_date - 14.days
      loop do
        deleted = Playlist.where("for_date < ?", cutoff).order(:id).limit(1000).destroy_all
        break if deleted.empty?
      end
    end
  end
end
