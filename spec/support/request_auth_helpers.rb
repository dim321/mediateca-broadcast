# frozen_string_literal: true

module RequestAuthHelpers
  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123456" }
  end
end

RSpec.configure do |config|
  config.include RequestAuthHelpers, type: :request
  config.include RequestAuthHelpers, type: :system
end
