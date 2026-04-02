# frozen_string_literal: true

return unless defined?(Lograge)

Rails.application.configure do
  next unless Rails.env.production?

  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.ignore_actions = [ "Rails::HealthController#show" ]
  config.lograge.custom_options = lambda do |event|
    payload = event.payload
    req = payload[:request]
    {
      request_id: req&.request_id,
      remote_ip: req&.remote_ip,
      organization_id: Current.organization&.id
    }.compact
  end
end
