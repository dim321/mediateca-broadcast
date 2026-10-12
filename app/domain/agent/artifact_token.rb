# frozen_string_literal: true

module Agent
  class ArtifactToken
    PURPOSE = :agent_artifact_upload
    TTL = 15.minutes

    def self.generate(public_id)
      verifier.generate(public_id, expires_in: TTL, purpose: PURPOSE)
    end

    def self.verify!(token)
      verifier.verify(token, purpose: PURPOSE)
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
