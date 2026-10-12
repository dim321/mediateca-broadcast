# frozen_string_literal: true

module Api
  module Agent
    class UploadsController < ActionController::API
      def update
        command = AgentCommand.find_by!(public_id: ::Agent::ArtifactToken.verify!(params[:token]))
        return head :unprocessable_content unless command.expects_upload?

        body = request.raw_post.to_s
        return render json: { error: "empty_body" }, status: :unprocessable_content if body.empty?
        return head :content_too_large if body.bytesize > ::Agent::StoreArtifact::MAX_BYTES

        expected = ::Agent::StoreArtifact::CONTENT_TYPES.fetch(command.command_type)
        return head :unsupported_media_type unless request.media_type == expected

        ::Agent::StoreArtifact.call(command:, io: StringIO.new(body), content_type: expected)
        head :no_content
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        head :forbidden
      end
    end
  end
end
