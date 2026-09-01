# frozen_string_literal: true

module Airtime
  # Hard channel rule for commercial / own_atmosphere placement (KTD7 / R9).
  # Soft commercial quota never substitutes for this check.
  class PlacementChannel < ServiceObject
    def self.assert!(...)
      new(...).assert!
    end

    def initialize(organization:, broadcast_point_group:, placement_kind:)
      @organization = organization
      @broadcast_point_group = broadcast_point_group
      @placement_kind = placement_kind.to_s
    end

    def call
      assert!
      true
    end

    def assert!
      if own_group?
        assert_own_group!
      else
        assert_foreign_group!
      end
    end

    private

    attr_reader :organization, :broadcast_point_group, :placement_kind

    def own_group?
      broadcast_point_group.organization_id == organization.id
    end

    def assert_own_group!
      return unless commercial?
      return unless includes_foreign_owned_screens?

      raise ArgumentError,
        "commercial placement on owned screens is only allowed via the owner organization group"
    end

    def assert_foreign_group!
      unless commercial?
        raise ArgumentError, "own/atmosphere placement is only allowed on your organization groups"
      end

      return if broadcast_point_group.owner_homogeneous?

      raise ArgumentError,
        "commercial placement on owned screens is only allowed via the owner organization group"
    end

    def commercial?
      placement_kind == "commercial"
    end

    def includes_foreign_owned_screens?
      broadcast_point_group.screens.any? do |screen|
        screen.owner_organization_id.present? &&
          screen.owner_organization_id != broadcast_point_group.organization_id
      end
    end
  end
end
