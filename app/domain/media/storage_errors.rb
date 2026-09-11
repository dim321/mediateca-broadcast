# frozen_string_literal: true

module Media
  module StorageErrors
    NETWORK = [
      Errno::ETIMEDOUT,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Net::OpenTimeout,
      Net::ReadTimeout
    ].freeze

    def self.network?(error)
      return false if error.nil?
      return true if NETWORK.any? { |klass| error.is_a?(klass) }
      return true if defined?(Seahorse::Client::NetworkingError) && error.is_a?(Seahorse::Client::NetworkingError)

      network?(error.cause)
    end
  end
end
