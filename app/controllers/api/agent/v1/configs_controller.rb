# frozen_string_literal: true

module Api
  module Agent
    module V1
      class ConfigsController < BaseController
        def show
          render json: ::Agent::ConfigBuilder.call(station: current_station)
        end
      end
    end
  end
end
