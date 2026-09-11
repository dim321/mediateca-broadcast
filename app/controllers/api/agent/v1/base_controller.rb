# frozen_string_literal: true

module Api
  module Agent
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_station!

        rescue_from ActiveRecord::RecordNotFound do
          render json: { error: "not_found" }, status: :not_found
        end

        rescue_from ActiveRecord::RecordInvalid do |error|
          render json: { error: "invalid_record", details: error.record.errors.full_messages }, status: :unprocessable_content
        end

        private

        def authenticate_station!
          @current_station = Station.find_by_agent_token(bearer_token)
          return if @current_station

          render json: { error: "unauthorized" }, status: :unauthorized
        end

        def bearer_token
          scheme, token = request.authorization.to_s.split(" ", 2)
          token if scheme == "Bearer"
        end

        attr_reader :current_station
      end
    end
  end
end
