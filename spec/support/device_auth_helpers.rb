# frozen_string_literal: true

module DeviceAuthHelpers
  def device_authorization_headers(token)
    { 'Authorization' => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include DeviceAuthHelpers, type: :request
end
