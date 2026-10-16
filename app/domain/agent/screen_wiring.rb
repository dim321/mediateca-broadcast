# frozen_string_literal: true

module Agent
  module ScreenWiring
    ADB_PORT = 5555

    module_function

    def wired?(screen)
      screen.network_registered? && ipv4_host?(screen.ip_address)
    end

    def adb_serial(screen)
      host = screen.ip_address.to_s.split("/").first
      return if host.blank?

      "#{host}:#{ADB_PORT}"
    end

    def mac(screen)
      screen.mac_address&.to_s.presence
    end

    def ipv4_host?(ip)
      return false if ip.blank?

      address = ip.is_a?(IPAddr) ? ip : IPAddr.new(ip.to_s.split("/").first)
      address.ipv4? && address.prefix == 32
    rescue IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      false
    end
  end
end
