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
          raise ActionController::ParameterMissing, :results unless rows.is_a?(Array)
          raise ActionController::ParameterMissing, :results unless raw_rows.size == rows.size

          rows.each_with_index.map do |row, index|
            sanitize_row(row, raw_rows.fetch(index))
          end
        end

        def raw_result_rows
          JSON.parse(request.raw_post).fetch("results").tap do |rows|
            raise ActionController::ParameterMissing, :results unless rows.is_a?(Array)
          end
        rescue JSON::ParserError, KeyError
          raise ActionController::ParameterMissing, :results
        end

        def sanitize_row(row, raw_row)
          valid_row = parameters_hash?(row) && parameters_hash?(raw_row)
          raise ActionController::ParameterMissing, :results unless valid_row

          permitted = row.permit(:command_id, :ok, :error, :finished_at).to_h
          return permitted unless raw_row.key?("result")

          permitted.merge("result" => sanitize_result(raw_row["result"]))
        end

        def sanitize_result(result)
          return result unless parameters_hash?(result)
          return {} unless result.key?("screens")

          { "screens" => sanitize_screens(result["screens"]) }
        end

        def sanitize_screens(screens)
          return screens unless screens.is_a?(Array)

          screens.map do |screen|
            next screen unless parameters_hash?(screen)

            ActionController::Parameters.new(screen).permit(:mac_address, :ip_address).to_h
          end
        end

        def parameters_hash?(value)
          value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
        end
      end
    end
  end
end
