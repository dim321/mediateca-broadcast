# frozen_string_literal: true

module Internal
  module Playlists
    class ReordersController < ApplicationController
      before_action :require_user
      before_action :set_playlist

      def update
        authorize @playlist, :reorder?
        ::Playlists::ReorderItems.call(playlist: @playlist, ordered_ids: reorder_ids)
        head :no_content
      rescue ArgumentError
        head :unprocessable_content
      end

      private

      def require_user
        return if Current.user

        head :unauthorized
      end

      def set_playlist
        @playlist = policy_scope(Playlist).find(params[:playlist_id])
      end

      def reorder_ids
        raw = params.permit(playlist_item_ids: [])[:playlist_item_ids]
        raise ArgumentError if raw.blank? || !raw.is_a?(Array)

        raw.map(&:to_i)
      end
    end
  end
end
