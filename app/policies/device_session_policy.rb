# frozen_string_literal: true

class DeviceSessionPolicy
  def initialize(device_token, broadcast_point)
    @device_token = device_token
    @broadcast_point = broadcast_point
  end

  def create?
    broadcast_point.present? && broadcast_point.device_token_digest.blank?
  end

  def show_current?
    broadcast_point.present?
  end

  def show_assignment?
    show_current?
  end

  def self.resolve_broadcast_point(device_token)
    return nil if device_token.blank?

    BroadcastPoint.where.not(device_token_digest: nil).find do |point|
      BCrypt::Password.new(point.device_token_digest).is_password?(device_token)
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end

  private

  attr_reader :device_token, :broadcast_point
end
