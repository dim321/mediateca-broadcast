# frozen_string_literal: true

module AgentAuthHelpers
  def agent_authorization_headers(token)
    { 'Authorization' => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include AgentAuthHelpers, type: :request
end
