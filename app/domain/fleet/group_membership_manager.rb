# frozen_string_literal: true

module Fleet
  class GroupMembershipManager < BaseService
    def initialize(point_group:)
      @point_group = point_group
    end

    def add(broadcast_point)
      ensure_same_organization!(broadcast_point)
      PointGroupMembership.create!(point_group: @point_group, broadcast_point: broadcast_point)
    end

    def remove(broadcast_point)
      ensure_same_organization!(broadcast_point)
      membership = @point_group.point_group_memberships.find_by!(broadcast_point: broadcast_point)
      membership.destroy!
    end

    private

    def ensure_same_organization!(broadcast_point)
      return if broadcast_point.organization_id == @point_group.organization_id

      raise ArgumentError, "broadcast_point must belong to the same organization as the group"
    end
  end
end
