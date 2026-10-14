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
          raw_rows = raw_result_rows
          raise ActionController::ParameterMissing, :results unless raw_rows.size == rows.size

          rows.each_with_index.map do |row, index|
            validate_result_shape!(raw_rows.fetch(index))
            row.permit(
              :command_id,
              :ok,
              :error,
              :finished_at,
              result: { screens: [ :mac_address, :ip_address ] }
            ).to_h
          end
        end

        def raw_result_rows
          JSON.parse(request.raw_post).fetch("results").tap do |rows|
            raise ActionController::ParameterMissing, :results unless rows.is_a?(Array)
          end
        rescue JSON::ParserError, KeyError
          raise ActionController::ParameterMissing, :results
        end

        def validate_result_shape!(row)
          return unless row.key?("result")

          result = row["result"]
          raise ActionController::ParameterMissing, :result unless parameters_hash?(result)
          return unless result.key?("screens")

          screens = result["screens"]
          valid_rows = screens.is_a?(Array) && screens.all? { parameters_hash?(_1) }
          raise ActionController::ParameterMissing, :screens unless valid_rows
        end

        def parameters_hash?(value)
          value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
        end
      end
    end
  end
end
