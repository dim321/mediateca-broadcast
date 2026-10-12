# frozen_string_literal: true

module Api
  module Agent
    module V1
      class CommandResultsController < BaseController
        def create
          ::Agent::Commands::Acknowledge.call(station: current_station, results: result_rows)
          head :ok
        rescue ::Agent::Commands::Acknowledge::Invalid, ActionController::ParameterMissing
          render json: { error: "invalid_result" }, status: :unprocessable_content
        end

        private

        def result_rows
          rows = params.require(:results)
          rows.map do |row|
            row.permit(:command_id, :ok, :error, :finished_at).to_h
          end
        end
      end
    end
  end
end
