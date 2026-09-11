# frozen_string_literal: true

module Api
  module Agent
    module V2
      class PackagesController < Api::Agent::V1::BaseController
        def show
          package = ::Playlists::PackageFromPlaylists.call(station: current_station)
          if stale?(etag: package[:etag], template: false)
            set_package_cache_control
            render json: package
          else
            set_package_cache_control
          end
        end

        private

        def set_package_cache_control
          response.set_header("Cache-Control", "private, must-revalidate")
        end
      end
    end
  end
end
