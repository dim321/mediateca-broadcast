# frozen_string_literal: true

module Api
  module V1
    class PlaybackAssignmentsController < BaseController
      before_action :authenticate_device!

      def current
        policy = DeviceSessionPolicy.new(bearer_token, current_broadcast_point)
        return render json: { error: "unauthorized" }, status: :unauthorized unless policy.show_assignment?

        assignment = Playback::CurrentAssignmentResolver.call(broadcast_point: current_broadcast_point)
        return head :no_content if assignment.nil?

        render json: assignment
      end
    end
  end
end
