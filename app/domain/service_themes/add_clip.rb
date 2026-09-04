# frozen_string_literal: true

module ServiceThemes
  class AddClip < BaseService
    def initialize(theme:, role:, file:, uploaded_by:)
      @theme = theme
      @role = role
      @file = file
      @uploaded_by = uploaded_by
    end

    def call
      rotation = theme.rotation_for(role)
      raise ArgumentError, "unknown service theme role #{role.inspect}" if rotation.blank?

      asset = nil
      ServiceTheme.transaction do
        asset = build_asset
        asset.save!
        rotation.rotation_items.create!(media_asset: asset)
      end
      Playlists::EnqueueRegen.from_rotation(rotation)
      asset
    rescue StandardError => e
      raise unless asset&.persisted? && Media::StorageErrors.network?(e)

      ProcessMediaMetadataJob.perform_later(asset.id)
      Playlists::EnqueueRegen.from_rotation(rotation)
      asset
    end

    private

    attr_reader :theme, :role, :file, :uploaded_by

    def build_asset
      MediaAsset.new(
        organization: theme.organization,
        uploaded_by: uploaded_by,
        content_type: :service,
        visibility: :organization
      ).tap { |asset| asset.file.attach(file) if file.present? }
    end
  end
end
