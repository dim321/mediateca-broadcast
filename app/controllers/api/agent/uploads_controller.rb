# frozen_string_literal: true

module Api
  module Agent
    class UploadsController < ActionController::API
      def update
        command = AgentCommand.find_by!(public_id: ::Agent::ArtifactToken.verify!(params[:token]))
        return head :unprocessable_content unless command.expects_upload?

        expected = ::Agent::StoreArtifact::CONTENT_TYPES.fetch(command.command_type)
        return head :unsupported_media_type unless request.media_type == expected

        length = request.content_length
        length = request.body.size if length.nil? && request.body.respond_to?(:size)
        return render json: { error: "empty_body" }, status: :unprocessable_content if length == 0
        return head :content_too_large if length && length > ::Agent::StoreArtifact::MAX_BYTES

        request.body.rewind if request.body.respond_to?(:rewind)

        ::Agent::StoreArtifact.call(command:, io: request.body, content_type: expected)
        head :no_content
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        head :forbidden
      end
    end
  end
end
