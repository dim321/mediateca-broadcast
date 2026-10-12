# frozen_string_literal: true

module Api
  module Agent
    module V1
      class CommandsController < BaseController
        def index
          etag = ::Agent::Commands::Queue.etag(station: current_station)
          response.headers["ETag"] = etag
          if none_match?(etag)
            head :not_modified
            return
          end

          render json: { commands: ::Agent::Commands::Queue.call(station: current_station) }
        end

        private

        def none_match?(etag)
          header = request.headers["If-None-Match"].to_s
          return false if header.blank?

          header.split(",").map(&:strip).any? { |candidate| candidate == etag || candidate == "W/#{etag}" }
        end
      end
    end
  end
end
