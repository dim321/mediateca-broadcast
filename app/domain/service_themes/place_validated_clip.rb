# frozen_string_literal: true

module ServiceThemes
  class PlaceValidatedClip < BaseService
    def initialize(theme:, role:, media_asset:)
      @theme = theme
      @role = role
      @media_asset = media_asset
    end

    def call
      rotation = theme.rotation_for(role)
      raise ArgumentError, "unknown service theme role #{role.inspect}" if rotation.blank?
      raise MediaAssets::Error, I18n.t("media_assets.content_validation.not_validated") unless placeable?

      item = rotation.rotation_items.create!(
        media_asset: media_asset,
        display_duration_seconds: media_asset.duration_seconds
      )
      Playlists::EnqueueRegen.from_rotation(rotation)
      item
    end

    private

    attr_reader :theme, :role, :media_asset

    def placeable?
      media_asset.content_validated? &&
        media_asset.content_type_service? &&
        media_asset.organization_id == theme.organization_id
    end
  end
end
