# frozen_string_literal: true

module Api
  module Agent
    module V1
      class TelemetriesController < BaseController
        def create
          ::Agent::RecordTelemetry.call(station: current_station, payload: telemetry_payload)
          head :accepted
        rescue ArgumentError, KeyError, ActionController::ParameterMissing, TypeError, ActiveRecord::RecordInvalid
          render json: { error: "invalid_telemetry" }, status: :unprocessable_content
        end

        private

        def telemetry_payload
          params.require(:reported_at)
          params.require(:station)
          raise ActionController::ParameterMissing, :screens unless params.key?(:screens)

          params.permit(
            :reported_at,
            station: %i[uptime_seconds package_etag broadcast_ok],
            screens: %i[screen_id reachable agent_ok playing url wakefulness stream_port broadcast_clients last_error]
          ).to_h
        end
      end
    end
  end
end
