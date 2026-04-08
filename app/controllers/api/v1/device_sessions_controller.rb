# frozen_string_literal: true

module Api
  module V1
    class DeviceSessionsController < BaseController
      POLL_INTERVAL_SECONDS = 45

      before_action :authenticate_device!, only: :current

      def create
        point = BroadcastPoint.find_by(venue_label: params[:pairing_code].to_s.strip)
        policy = DeviceSessionPolicy.new(nil, point)

        return render json: { error: "invalid_pairing_code" }, status: :unprocessable_entity unless point
        return render json: { error: "already_paired" }, status: :conflict unless policy.create?

        token = SecureRandom.hex(32)
        point.update!(
          device_token_digest: BCrypt::Password.create(token),
          status: :online
        )

        render json: {
          device_token: token,
          broadcast_point_id: point.id,
          poll_interval_seconds: POLL_INTERVAL_SECONDS
        }, status: :created
      end

      def current
        point = current_broadcast_point

        render json: {
          broadcast_point_id: point.id,
          organization_id: point.organization_id,
          time_zone: point.time_zone.presence || point.organization.time_zone,
          poll_interval_seconds: POLL_INTERVAL_SECONDS
        }
      end
    end
  end
end
