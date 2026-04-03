# frozen_string_literal: true

module Playlists
  class PlaylistItemComponent < ViewComponent::Base
    def initialize(playlist:, item:)
      @playlist = playlist
      @item = item
    end

    attr_reader :playlist, :item
  end
end
