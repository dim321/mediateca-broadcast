# frozen_string_literal: true

module Agent
  module Screens
    class Synchronize < BaseService
      def initialize(station:, screens:)
        @station = station
        @screens = screens
      end

      def call
        pairs = NormalizeDiscovery.call(screens:)

        station.with_lock { synchronize(pairs) }
      ensure
        station.screens.reset
      end

      private

      attr_reader :station, :screens

      def synchronize(pairs)
        existing_by_mac = station.screens.where.not(mac_address: nil).index_by { _1.mac_address.to_s }
        discovered_macs = pairs.map(&:mac_address)

        unregister_missing(discovered_macs)
        update_existing(pairs, existing_by_mac)
        create_unknown(pairs, existing_by_mac)
      end

      def unregister_missing(discovered_macs)
        missing = station.screens.where(mac_address: nil)
          .or(station.screens.where.not(mac_address: discovered_macs))

        missing.find_each do |screen|
          screen.update!(network_registered: false)
        end
      end

      def update_existing(pairs, existing_by_mac)
        pairs.each do |pair|
          screen = existing_by_mac[pair.mac_address]
          screen&.update!(ip_address: pair.ip_address, network_registered: true)
        end
      end

      def create_unknown(pairs, existing_by_mac)
        pairs
          .reject { existing_by_mac.key?(_1.mac_address) }
          .sort_by { _1.ip_address.to_i }
          .each { create_screen(_1) }
      end

      def create_screen(pair)
        station.screens.reset
        station.screens.create!(
          mac_address: pair.mac_address,
          ip_address: pair.ip_address,
          network_registered: true
        )
      end
    end
  end
end
