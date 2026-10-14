# frozen_string_literal: true

require "ipaddr"

module Agent
  module Screens
    class NormalizeDiscovery < BaseService
      class Invalid < StandardError; end

      Pair = Data.define(:mac_address, :ip_address)

      MAC_PATTERNS = [
        /\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/i,
        /\A(?:[0-9a-f]{2}-){5}[0-9a-f]{2}\z/i,
        /\A[0-9a-f]{12}\z/i,
        /\A[0-9a-f]{4}(?:\.[0-9a-f]{4}){2}\z/i
      ].freeze
      IPV4_PATTERN = /\A(?:\d{1,3}\.){3}\d{1,3}\z/

      def initialize(screens:)
        @screens = screens
      end

      def call
        raise Invalid unless screens.is_a?(Array)

        normalize_rows.uniq.tap { validate_unique_addresses!(_1) }
      rescue Invalid
        raise
      rescue KeyError, TypeError, NoMethodError, ArgumentError, IPAddr::Error
        raise Invalid
      end

      private

      attr_reader :screens

      def normalize_rows
        screens.map do |row|
          attributes = row.to_h.symbolize_keys
          Pair.new(
            mac_address: normalize_mac(attributes.fetch(:mac_address)),
            ip_address: normalize_ip(attributes.fetch(:ip_address))
          )
        end
      end

      def normalize_mac(value)
        raise Invalid unless value.is_a?(String) && MAC_PATTERNS.any? { value.match?(_1) }

        value.gsub(/[^0-9a-f]/i, "").downcase.scan(/../).join(":")
      end

      def normalize_ip(value)
        raise Invalid unless value.is_a?(String) && value.match?(IPV4_PATTERN)

        IPAddr.new(value).tap { raise Invalid unless _1.ipv4? }
      end

      def validate_unique_addresses!(pairs)
        raise Invalid unless pairs.map(&:mac_address).uniq.size == pairs.size
        raise Invalid unless pairs.map(&:ip_address).uniq.size == pairs.size
      end
    end
  end
end
