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
          media_plan = eligible_media_plan_for!(screen:, media_asset_id: event[:media_asset_id])

          PlayLog.create!(
            organization: media_plan.organization,
            screen:,
            media_asset: media_plan.rotation.media_assets.find(event[:media_asset_id]),
            started_at: event[:started_at],
            source: :agent
          )
        end

        def eligible_media_plan_for!(screen:, media_asset_id:)
          now = Time.current
          horizon = now + current_station.offline_cache_hours.hours

          media_plan = MediaPlan
            .joins(broadcast_point_group: :screens, rotation: :rotation_items)
            .where(screens: { id: screen.id })
            .where(rotation_items: { media_asset_id: media_asset_id })
            .where("media_plans.starts_at <= ? AND media_plans.ends_at >= ?", horizon, now)
            .distinct
            .first

          raise ActiveRecord::RecordNotFound if media_plan.blank?

          media_plan
        end
      end
    end
  end
end
