# frozen_string_literal: true

require "capybara/rails"
require "capybara/rspec"
require "capybara/cuprite"

CUPRITE_BROWSER_PATH = ENV.fetch("CUPRITE_BROWSER_PATH", "/usr/bin/chromium")

def js_system_specs_enabled?
  ENV["RUN_JS_SYSTEM_SPECS"] == "1" && File.executable?(CUPRITE_BROWSER_PATH)
end

Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    headless: true,
    browser_path: CUPRITE_BROWSER_PATH,
    browser_options: {
      "no-sandbox": nil,
      "disable-dev-shm-usage": nil,
      "disable-gpu": nil
    },
    process_timeout: 15,
    timeout: 10
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, :js, type: :system) do
    skip "Set RUN_JS_SYSTEM_SPECS=1 with Chromium at #{CUPRITE_BROWSER_PATH}" unless js_system_specs_enabled?

    driven_by :cuprite
  end
end
