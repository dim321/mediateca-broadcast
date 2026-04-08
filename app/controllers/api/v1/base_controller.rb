# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      private

      def bearer_token
        request.authorization.to_s.split(" ", 2).last
      end

      def authenticate_device!
        token = bearer_token
        @current_broadcast_point = DeviceSessionPolicy.resolve_broadcast_point(token)
        policy = DeviceSessionPolicy.new(token, @current_broadcast_point)
        return if policy.show_current?

        render json: { error: "unauthorized" }, status: :unauthorized
      end

      def current_broadcast_point
        @current_broadcast_point
      end
    end
  end
end
