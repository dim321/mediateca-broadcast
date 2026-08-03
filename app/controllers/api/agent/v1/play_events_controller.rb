# frozen_string_literal: true

module Api
  module Agent
    module V1
      class PlayEventsController < BaseController
        def create
          play_logs = PlayLog.transaction { events_params.map(&method(:create_play_log)) }

          render json: { play_log_ids: play_logs.map(&:id) }, status: :created
        end

        private

        def events_params
          params.require(:events).map do |event|
            event.permit(:screen_id, :media_asset_id, :started_at)
          end
        end

        def create_play_log(event)
          media_asset = MediaAsset.find(event[:media_asset_id])

          PlayLog.create!(
            organization: media_asset.organization,
            screen: current_station.screens.find(event[:screen_id]),
            media_asset:,
            started_at: event[:started_at],
            source: :agent
          )
        end
      end
    end
  end
end
