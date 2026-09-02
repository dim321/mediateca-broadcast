# frozen_string_literal: true

module Api
  module Agent
    module V1
      class PlayEventsController < BaseController
        def create
          play_logs = PlayLog.transaction { events_params.map { |event| create_play_log(event) } }

          render json: { play_log_ids: play_logs.map(&:id) }, status: :created
        end

        private

        def events_params
          params.require(:events).map do |event|
            event.permit(:screen_id, :media_asset_id, :started_at)
          end
        end

        def create_play_log(event)
          screen = current_station.screens.find(event[:screen_id])
          resolved = ::Playlists::ResolvePlayEvent.call(
            station: current_station,
            screen: screen,
            media_asset_id: event[:media_asset_id]
          )
          raise ActiveRecord::RecordNotFound if resolved.nil?

          PlayLog.create!(
            organization: resolved.organization,
            screen:,
            media_asset: resolved.media_asset,
            started_at: event[:started_at],
            source: :agent
          )
        end
      end
    end
  end
end
