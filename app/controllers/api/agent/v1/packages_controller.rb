# frozen_string_literal: true

module Api
  module Agent
    module V1
      class PackagesController < BaseController
        def show
          package = ::Agent::PackageBuilder.call(station: current_station)

          response.set_header("ETag", %("#{package[:etag]}"))
          render json: package
        end
      end
    end
  end
end
